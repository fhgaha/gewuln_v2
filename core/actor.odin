package core

import "../packages/toml"
import "core:encoding/json"
import "core:fmt"
import "core:strings"
import r "vendor:raylib"

Actor :: struct {
	initialised:           bool,
	name:                  string,
	pos:                   vec3,
	yaw:                   f32, //in rads
	speed, rot_speed:      f32,
	model:                 r.Model,
	bounding_box_original: r.BoundingBox,
	bounding_box:          r.BoundingBox,
	state:                 Actor_State,
	animator:              Animator,

	//neck rotation
	neck_bone_index:       i32,
	neck_current_delta:    r.Quaternion,
	dialogue_cameras:      map[string]r.Camera3D,
}

Actor_State :: enum {
	IDLE,
	WALK,
	INTERACT,
	DIALOGUE,
}

actor_state_strings := [Actor_State]string {
	.IDLE     = "idle",
	.WALK     = "walk",
	.INTERACT = "interact",
	.DIALOGUE = "dialogue",
}

Input_State :: struct {
	move_dir:       f32, // -1 to 1 (Forward/Back)
	turn_dir:       f32, // -1 to 1 (Left/Right)
	wants_interact: bool,
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

create_actor :: proc(actor_table: ^toml.Table) -> (actor: Actor, ok: bool) {
	actor_name := toml.get_string_panic(actor_table, "name")
	model_path := toml.get_string_panic(actor_table, "model")
	collider_path, coll_ok := toml.get_string(actor_table, "collider")
	model_path_c := strings.clone_to_cstring(model_path)

	// Load resources
	actor_model := r.LoadModel(model_path_c)
	if !r.IsModelValid(actor_model) {
		return {}, false
	}

	has_collider: bool
	actor_coll_model: r.Model
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
	cameras_json, cameras_json_ok := model_glb_json.(json.Object)["cameras"].(json.Array)
	dialogue_cameras: map[string]r.Camera3D

	for node in model_glb_json.(json.Object)["nodes"].(json.Array) {
		name_val := node.(json.Object)["name"]
		if name_val != nil {
			name := strings.to_lower(name_val.(json.String))
			is_dialogue_camera :=
				strings.contains(name, "camera") && strings.contains(name, "dialogue")
			if is_dialogue_camera {
				camera, _ := parse_camera3d_from_glb(node.(json.Object), &cameras_json)
				dialogue_cameras[name] = camera
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
	actor.bounding_box.min += new_pos - old_pos
	actor.bounding_box.max += new_pos - old_pos

	if actor.pos != old_pos && .print_debug_info in flags {
		fmt.println(actor.name, ": pos =", actor.pos)
	}
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

	if new_yaw != old_yaw && .print_debug_info in flags {
		fmt.println(actor.name, ": yaw =", new_yaw * r.RAD2DEG)
	}
}

//actor states

handle_idle :: proc(dt: f32) {
	yaw := main_actor.yaw + input.turn_dir * main_actor.rot_speed * dt
	actor_update_yaw(main_actor, yaw)

	play_anim(&main_actor.animator, .IDLE)

	// state transitions	
	walk_cond := input.move_dir != 0

	interact_trg, interact_tgr_found := get_interactable_colliding_actor(
		cur_level().interactables[:],
		main_actor,
	)

	interact_cond := input.wants_interact && interact_tgr_found
	switch {
	case walk_cond:
		main_actor.state = .WALK
		fmt.println(main_actor.name, ": handle_walk")
	case interact_cond:
		main_actor.state = .INTERACT
		fmt.println(main_actor.name, ": handle_interact")
	}
}


handle_walk :: proc(dt: f32) {
	yaw := main_actor.yaw + input.turn_dir * main_actor.rot_speed * dt
	actor_update_yaw(main_actor, yaw)

	play_anim(&main_actor.animator, .WALK)

	desired_dpos: vec3 = input.move_dir * main_actor.speed * dt * actor_dir(main_actor)
	dpos := resolve_slide(desired_dpos, main_actor.bounding_box, cur_level().walk_area_tris[:])
	actor_update_pos(main_actor, main_actor.pos + dpos)


	// state transitions
	interact_trg, interact_trg_found := get_interactable_colliding_actor(
		cur_level().interactables[:],
		main_actor,
	)

	interact_cond := interact_trg_found && input.wants_interact
	idle_cond := input.move_dir == 0
	switch {
	case interact_cond:
		main_actor.state = .INTERACT
		fmt.println(main_actor.name, ": handle_interact")
	case idle_cond:
		main_actor.state = .IDLE
		fmt.println(main_actor.name, ": handle_idle")
	}
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


handle_interact :: proc() {
	play_anim(&main_actor.animator, .INTERACT)

	animation_ended := last_frame_reached(&main_actor.animator)

	if animation_ended {
		interact()
	}


	//state conditions	
	walk_cond := animation_ended && input.move_dir != 0
	idle_cond := animation_ended
	switch {
	//TODO
	case true:
		main_actor.state = .DIALOGUE
		fmt.println(main_actor.name, ": handle_dialogue")
	case walk_cond:
		main_actor.state = .WALK
		fmt.println(main_actor.name, ": handle_walk")
	case idle_cond:
		main_actor.state = .IDLE
		fmt.println(main_actor.name, ": handle_idle")
	}
}


get_interactable_colliding_actor :: proc(
	interactables: []Interactable,
	actor: ^Actor,
) -> (
	colliding: [dynamic]Interactable,
	found: bool,
) {
	for &intr in interactables {
		mesh := get_interactable_mesh(&intr)
		col := r.CheckCollisionBoxes(actor.bounding_box, r.GetMeshBoundingBox(mesh))
		if (col) {
			append(&colliding, intr)
		}
	}

	if false do print_intercactables_colliding_with_actor(colliding)

	print_intercactables_colliding_with_actor :: proc(colliding: [dynamic]Interactable) {
		names_slice := make([]string, len(colliding)); defer delete(names_slice)
		for collider, idx in colliding {
			names_slice[idx] = collider.name
		}
		fmt.println("interactables colliding actor: ", names_slice)
	}

	// save in level
	cur_level().intersected_interactables = colliding

	if len(colliding) == 0 do return


	found = true
	return
}

handle_dialogue :: proc() {
	// here:  ["mona", "Hey, how's it going?"]
	// here:  ["cleaner_a", "Busy day. Floor's not gonna mop itself."]
	// here:  ["mona", "Fair enough."]
	// here:  ["cleaner_a", "..."]

	if len(cur_dialogue.lines) == 0 {
		interact_trg, interact_tgr_found := get_interactable_colliding_actor(
			cur_level().interactables[:],
			main_actor,
		)
		cur_dialogue = interact_trg[0].data.(Dialogue_Data)
	}

	if r.IsKeyReleased(.SPACE) {
		cur_dialogue.cur_idx += 1
		if cur_dialogue.cur_idx >= len(cur_dialogue.lines) {
			cur_dialogue.cur_idx = 0
		}
	}
}
