package gewuln

import "../packages/toml"
import "core:encoding/json"
import "core:fmt"
import "core:math"
import "core:math/rand"
import "core:slice"
import "core:strings"
import r "vendor:raylib"

Actor :: struct {
	initialised:                         bool,
	name:                                string,
	pos:                                 vec3,
	yaw:                                 f32, //in rads
	speed, rot_speed:                    f32,
	model:                               r.Model,
	bounding_box_original, bounding_box: r.BoundingBox,
	state:                               Actor_State,
	animator:                            Animator,

	//neck rotation
	neck_bone_index:                     i32,
	neck_current_delta:                  r.Quaternion,
	dialogue_cameras:                    [dynamic]r.Camera3D,
}

Input_State :: struct {
	move_dir:         f32, // -1 to 1 (Forward/Back)
	turn_dir:         f32, // -1 to 1 (Left/Right)
	wants_interact:   bool,
	dialogue_advance: bool,
}

Actor_State :: enum {
	IDLE,
	WALK,
	INTERACT,
	DIALOGUE,
	STAIR,
}

actor_state_strings := [Actor_State]string {
	.IDLE     = "idle",
	.WALK     = "walk",
	.INTERACT = "interact",
	.DIALOGUE = "dialogue",
	.STAIR    = "stair",
}

Actor_State_Transition :: struct {
	from, to: Actor_State,
	cond:     proc() -> bool,
}

actor_transitions := []Actor_State_Transition {
	//from, to, condition
	// IDLE
	{.IDLE, .WALK, proc() -> bool {return input.move_dir != 0}},
	{
		.IDLE,
		.INTERACT,
		proc() -> bool {return input.wants_interact && main_actor_state.interact_target_found},
	},
	//
	// WALK
	{
		.WALK,
		.INTERACT,
		proc() -> bool {return input.wants_interact && main_actor_state.interact_target_found},
	},
	{.WALK, .IDLE, proc() -> bool {return input.move_dir == 0}},
	// {.INTERACT, .STAIR,    proc() -> bool { return interact_anim_done && stair_target_found }},
	//
	// INTERACT
	{
		.INTERACT,
		.DIALOGUE,
		proc() -> bool {return(
				main_actor_state.interact_anim_ended &&
				main_actor_state.dialogue_target_found \
			)},
	},
	{
		.INTERACT,
		.WALK,
		proc() -> bool {return main_actor_state.interact_anim_ended && input.move_dir != 0},
	},
	{.INTERACT, .IDLE, proc() -> bool {return main_actor_state.interact_anim_ended}},
	//
	// DIALOGUE
	{.DIALOGUE, .IDLE, proc() -> bool {return main_actor_state.dialogue_ended}},
}

actor_set_state :: proc(actor: ^Actor, new: Actor_State) {
	if actor.state == new do return
	fmt.println(actor.name, "->", actor_state_strings[new])
	actor.state = new
}

actor_transition_state :: proc(actor: ^Actor) {
	for &t in actor_transitions {
		if t.from == actor.state && t.cond() {
			actor_set_state(actor, t.to)
			return
		}
	}
}

create_actors_from_toml :: proc(toml_table: ^toml.Table) -> (actors: map[string]Actor) {
	for a in toml_table["actors"].(^toml.List) {
		actor_name := toml.get_string_panic(a.(^toml.Table), "name")
		actor, ok := create_actor(a.(^toml.Table))
		if !ok do panic(fmt.tprintf("couldnt create actor: %v", actor))
		actors[actor_name] = actor
	}
	return
}

create_actor :: proc(actor_toml: ^toml.Table) -> (actor: Actor, ok: bool) {
	actor_name := toml.get_string_panic(actor_toml, "name")
	model_path := toml.get_string_panic(actor_toml, "model")
	collider_path, coll_ok := toml.get_string(actor_toml, "collider")
	model_path_c := strings.clone_to_cstring(model_path)

	// Load resources
	actor_model := r.LoadModel(model_path_c)
	if !r.IsModelValid(actor_model) {
		return {}, false
	}

	has_collider: bool
	actor_coll_model: r.Model
	defer r.UnloadModel(actor_coll_model)
	if coll_ok && collider_path != "" {
		actor_coll_model = r.LoadModel(strings.clone_to_cstring(collider_path))
		has_collider = true
		if !r.IsModelValid(actor_coll_model) {
			r.UnloadModel(actor_model)
			return {}, false
		}
	}

	// Load animations
	anim_count: i32
	anims := r.LoadModelAnimations(model_path_c, &anim_count)
	if anims == nil || anim_count == 0 {
		r.UnloadModel(actor_model)
		r.UnloadModel(actor_coll_model)
		return {}, false
	}

	bb := r.GetModelBoundingBox(actor_coll_model)

	animator := Animator {
		anims_count = anim_count,
		anims       = anims,
	}
	fill_animation_names(&animator)

	// parse dialogue cameras
	model_glb_json := get_json_chunk_from_glb(model_path)
	defer json.destroy_value(model_glb_json)
	cameras_json, cameras_json_ok := model_glb_json.(json.Object)["cameras"].(json.Array)
	assert(cameras_json_ok)
	dialogue_cameras: [dynamic]r.Camera3D

	for node in model_glb_json.(json.Object)["nodes"].(json.Array) {
		name_val := node.(json.Object)["name"]
		if name_val != nil {
			name := strings.to_lower(name_val.(json.String))
			is_dialogue_camera :=
				strings.contains(name, "camera") && strings.contains(name, "dialogue")
			if is_dialogue_camera {
				camera, camera_ok := parse_camera3d_from_glb(node.(json.Object), &cameras_json)
				// assert(camera_ok)
				append(&dialogue_cameras, camera)
			}
		}
	}

	actor = Actor {
		initialised           = true,
		name                  = actor_name,
		pos                   = 0,
		yaw                   = yaw_from_transform(actor_model.transform),
		speed                 = 2,
		rot_speed             = 4,
		model                 = actor_model,
		bounding_box_original = bb,
		bounding_box          = bb,
		state                 = .IDLE,
		animator              = animator,
		neck_bone_index       = -1,
		neck_current_delta    = r.Quaternion(1),
		dialogue_cameras      = dialogue_cameras,
	}
	ok = true
	return
}

delete_actor :: proc(actor: ^Actor) {
	r.UnloadModel(actor.model)
	r.UnloadModelAnimations(actor.animator.anims, actor.animator.anims_count)
	err := delete(actor.dialogue_cameras); assert(err == .None)
}

actor_pos :: proc(actor: ^Actor) -> vec3 {
	return pos_from_transform(actor.model.transform)
}

actor_dir :: proc(actor: ^Actor) -> vec3 {
	fwd, _, _: vec3 = actor_orientation(actor)
	return fwd
}

actor_orientation :: proc(actor: ^Actor) -> (fwd, left, up: vec3) {
	fwd, left, up = orientation_from_transform(actor.model.transform)
	return
}

actor_update_pos_and_yaw :: proc(actor: ^Actor, pos: vec3, yaw_deg: f32) {
	actor_update_pos(actor, pos)
	actor_update_yaw(actor, yaw_deg * r.DEG2RAD)
}

actor_update_pos :: proc(actor: ^Actor, new_pos: vec3) {
	old_pos := actor.pos
	actor.pos = new_pos
	delta := new_pos - old_pos
	actor.bounding_box.min += delta
	actor.bounding_box.max += delta

	for &c in actor.dialogue_cameras {
		c.position += delta
		c.target += delta
	}

	if actor.pos != old_pos && .print_debug_info in flags {
		fmt.println(actor.name, ": pos =", actor.pos)
	}

	// print(actor.name, actor.pos, actor.dialogue_cameras[:][0].position)
}

actor_update_yaw :: proc(actor: ^Actor, yaw: f32) {
	old_yaw := actor.yaw
	new_yaw := clamp_angle(yaw)
	actor.yaw = new_yaw

	// instead of this
	// rot := r.MatrixRotateY(actor.yaw)
	// transl := r.MatrixTranslate(actor.pos.x, actor.pos.y, actor.pos.z)
	// actor.model.transform = transl * rot
	// just set transform to rotation since raylib in DrawModel multiplies position
	// to model's transform
	actor.model.transform = r.MatrixRotateY(new_yaw)

	q := r.QuaternionFromAxisAngle(UP, new_yaw - old_yaw)
	for &c in actor.dialogue_cameras {
		c.position = actor.pos + r.Vector3RotateByQuaternion(c.position - actor.pos, q)
		c.target = actor.pos + r.Vector3RotateByQuaternion(c.target - actor.pos, q)
	}

	if new_yaw != old_yaw && .print_debug_info in flags {
		fmt.println(actor.name, ": yaw =", new_yaw * r.RAD2DEG)
	}
}

//
//actor states
//

// per simulation step — continuous behavior
update_actor_step :: proc(actor: ^Actor, dt: f32) {
	#partial switch actor.state {
		case .IDLE: handle_idle(actor, dt)
		case .WALK: handle_walk(actor, dt)
	}
}

// once per frame — input events & one-shot actions
update_actor_events :: proc(actor: ^Actor) {
	#partial switch actor.state {
		case .INTERACT: handle_interact(actor)
		case .DIALOGUE: handle_dialogue(actor)
		case .STAIR: //handle_stair(actor)
	}
}

handle_idle :: proc(actor: ^Actor, dt: f32) {
	main_actor_state.dialogue_ended = false

	yaw := main_actor.yaw + input.turn_dir * main_actor.rot_speed * dt
	actor_update_yaw(main_actor, yaw)

	play_anim(&actor.animator, .IDLE)
}


handle_walk :: proc(actor: ^Actor, dt: f32) {
	yaw := main_actor.yaw + input.turn_dir * main_actor.rot_speed * dt
	actor_update_yaw(main_actor, yaw)

	play_anim(&main_actor.animator, .WALK)

	desired_dpos: vec3 = input.move_dir * main_actor.speed * dt * actor_dir(main_actor)
	dpos := resolve_slide(desired_dpos, main_actor.bounding_box, cur_level().walk_area_tris[:])
	actor_update_pos(main_actor, main_actor.pos + dpos)
}


// Separate this so you can use it for NPCs or other entities later
resolve_slide :: proc(desired: vec3, bb: r.BoundingBox, area: []tri3) -> (result: vec3) {
	remaining := desired

	for _ in 0 ..< 3 {
		if remaining == 0 do break

		// Helper to check if a potential move is valid
		is_valid :: proc(offset: vec3, bb: r.BoundingBox, area: []tri3) -> bool {
			moved_bb := bb
			moved_bb.min += offset
			moved_bb.max += offset
			return bounding_box_inside_walk_area(moved_bb, area)
		}

		if is_valid(remaining, bb, area) {
			result = remaining
			break
		}

		// Try axis-splitting for sliding against walls
		move_x := vec3{remaining.x, 0, 0}
		move_z := vec3{0, 0, remaining.z}

		can_x := is_valid(move_x, bb, area)
		can_z := is_valid(move_z, bb, area)

		if can_x && can_z {
			result += remaining
			break
		} else if can_x {
			result += move_x
			remaining.z = 0
		} else if can_z {
			result += move_z
			remaining.x = 0
		} else {
			remaining *= 0.5 // Dampen if stuck
		}
	}
	return
}


handle_interact :: proc(actor: ^Actor) {
	skip_interact_anim: bool = true

	if skip_interact_anim {
		main_actor_state.interact_anim_ended = true
		interact()
	} else {
		play_anim(&main_actor.animator, .INTERACT)
		main_actor_state.interact_anim_ended = last_frame_reached(&main_actor.animator)

		if main_actor_state.interact_anim_ended {
			interact()
		}
	}

	//update actor state
	is_dialogue, is_stair: bool
	if main_actor_state.interact_target_found {
		_, is_dialogue = &main_actor_state.intersected_interactables[0].data.(Dialogue_Data)
		_, is_stair = &main_actor_state.intersected_interactables[0].data.(Stair_Data)
	}
	dialogue_target_found :=
		main_actor_state.interact_anim_ended &&
		main_actor_state.interact_target_found &&
		is_dialogue
	main_actor_state.dialogue_target_found = dialogue_target_found
}

get_interactable_colliding_actor :: proc(
	interactables: []Interactable,
	actor: ^Actor,
) -> (
	intersected: []Interactable,
	found: bool,
) {
	tmp: [dynamic]Interactable

	for &intr in interactables {
		mesh := get_interactable_mesh(&intr)
		if r.CheckCollisionBoxes(actor.bounding_box, r.GetMeshBoundingBox(mesh)) {
			append(&tmp, intr)
		}
	}

	// hand the buffer to the level (it's the owner now); free yesterday's first
	delete(main_actor_state.intersected_interactables)
	main_actor_state.intersected_interactables = tmp

	// same buffer as the field — valid until the NEXT call to this proc
	intersected = tmp[:]
	found = len(intersected) > 0
	return
}

handle_dialogue :: proc(actor: ^Actor) {
	// here:  ["mona", "Hey, how's it going?"]
	// here:  ["cleaner_a", "Busy day. Floor's not gonna mop itself."]
	// here:  ["mona", "Fair enough."]
	// here:  ["cleaner_a", "..."]

	play_anim(&main_actor.animator, .IDLE)

	if len(cur_dialogue.lines) == 0 {
		found_dialogue: bool
		some_dialogue: Dialogue_Data
		for i := len(main_actor_state.intersected_interactables) - 1; i >= 0; i -= 1 {
			some_dialogue, found_dialogue = main_actor_state.intersected_interactables[i].data.(Dialogue_Data)
			if found_dialogue {
				break
			}
		}
		assert(found_dialogue)

		// cur_dialogue = slice.last(interact_targets[:]).data.(Dialogue_Data)
		cur_dialogue = some_dialogue
		cur_dialogue.cashed_cam = cur_level().cam
		use_actor_camera_while_talking()
	}


	if r.IsKeyReleased(.SPACE) {
		cur_dialogue.cur_idx += 1

		idx_ok := cur_dialogue.cur_idx < len(cur_dialogue.lines)
		// use actor camera while talking
		if idx_ok {
			use_actor_camera_while_talking()
		} else {
			//reset
			cur_level().cam = cur_dialogue.cashed_cam
			cur_dialogue = {}

			main_actor_state.dialogue_ended = true
		}
	}
}

use_actor_camera_while_talking :: proc() {
	speaker := cur_level().actors[get_dialogue_speaker_name()]
	cam_ptrs := make([]^r.Camera3D, len(speaker.dialogue_cameras[:]))
	for i := 0; i < len(cam_ptrs); i += 1 {
		cam_ptrs[i] = &speaker.dialogue_cameras[i]
	}
	dial_cam_idx := rand.int_range(0, len(cam_ptrs))
	cur_level().cam = cam_ptrs[dial_cam_idx]
}

actor_is_looking_at_point :: proc(
	actor: ^Actor,
	point: vec3,
) -> (
	target_direction: r.Quaternion,
	ok: bool,
) {
	animator := &actor.animator
	anim := &animator.anims[animator.anim_idx]
	neck_idx := int(actor.neck_bone_index)
	frame_idx := animator.anim_cur_frame

	neck_local, neck_local_ok := get_bone_transform(
		&actor.model,
		neck_idx,
		anim^.framePoses[frame_idx],
	)
	assert(neck_local_ok, "cant get bone transform")
	neck_pos := neck_local.translation + actor.pos
	world_dir := r.Vector3Normalize(point - neck_pos)
	local_dir := r.Vector3Normalize(r.Vector3Transform(world_dir, r.MatrixRotateY(-actor.yaw)))
	angle_y := vec3_angle(vec3{local_dir.x, 0, local_dir.z}, FORWARD)
	if angle_y * r.RAD2DEG < ACTOR_NECK_MAX_YAW_DEG {
		if .show_gizmos in flags {
			draw_debug_line(neck_pos, point, r.PURPLE)
		}
		return neck_target_rotation(local_dir), true
	}
	return r.Quaternion(1), false
}

@(private = "file")
neck_target_rotation :: proc(local_dir: vec3) -> r.Quaternion {
	pitch := math.asin(clamp(local_dir.y, -1, 1))
	pitch = clamp(
		pitch,
		-ACTOR_NECK_MAX_PITCH_DEG * r.DEG2RAD,
		ACTOR_NECK_MAX_PITCH_DEG * r.DEG2RAD,
	)
	horiz_len := math.sqrt(local_dir.x * local_dir.x + local_dir.z * local_dir.z)
	clamped_dir := local_dir
	if horiz_len > 0.001 {
		scale := math.cos(pitch) / horiz_len
		clamped_dir.x *= scale
		clamped_dir.z *= scale
	} else {
		clamped_dir.x = 0
		clamped_dir.z = math.cos(pitch)
	}
	clamped_dir.y = math.sin(pitch)
	lookat := r.MatrixInvert(r.MatrixLookAt(vec3{0, 0, 0}, -clamped_dir, UP))
	return r.QuaternionFromMatrix(lookat)
}

handle_stair :: proc(actor: ^Actor, data: Stair_Data) {
	for data.cur_path_point_idx != len(data.path) {
		cur_pt := data.path[data.cur_path_point_idx]
		actor_walk_continuosly(actor, cur_pt, DT)
	}
}

// run until arrived
actor_walk_continuosly :: proc(actor: ^Actor, target: vec3, dt: f32) -> (arrived: bool) {
	direction := target - actor.pos
	distance := r.Vector3Length(direction)
	ARRIVAL_THRESHOLD: f32 = 0.1

	if distance < ARRIVAL_THRESHOLD {
		actor.pos = target // snap to avoid jitter
		actor.state = .IDLE
		return true
	}

	actor_update_pos(actor, target)
	return false
}
