package core

import "core:fmt"
import r "vendor:raylib"

Actor :: struct {
	pos:               vec3,
	speed, rot_speed:  f32,
	model:             r.Model,
	bounding_box_loc:  r.BoundingBox,
	bounding_box_glob: r.BoundingBox,
	state:             Actor_State,
	animator:          Animator,
}

Actor_State :: enum {
	IDLE,
	WALK,
	INTERACT,
}

actor_state_strings := [Actor_State]string {
	.IDLE     = "idle",
	.WALK     = "walk",
	.INTERACT = "interact",
}

create_actor :: proc(actor: ^Actor, actor_path, collider_path: cstring) -> bool {
	// Load resources
	actor_model := r.LoadModel(actor_path)
	if !r.IsModelValid(actor_model) {
		return false
	}

	actor_coll_model := r.LoadModel(collider_path)
	if !r.IsModelValid(actor_coll_model) {
		r.UnloadModel(actor_model)
		return false
	}

	// Load animations
	anim_count: i32
	anims := r.LoadModelAnimations(actor_path, &anim_count)
	if anims == nil || anim_count == 0 {
		r.UnloadModel(actor_model)
		r.UnloadModel(actor_coll_model)
		return false
	}

	bb := r.GetModelBoundingBox(actor_coll_model)

	// Assemble the actor
	actor^ = Actor {
		speed = 2,
		rot_speed = 4,
		model = actor_model,
		bounding_box_loc = bb,
		bounding_box_glob = bb,
		state = .IDLE,
		animator = Animator{anims_count = anim_count, anims = anims},
	}
	fill_animation_names(&actor.animator)

	return true
}

actor_pos :: proc(actor: ^Actor) -> vec3 {
	return pos_from_transform(actor.model.transform)
}

actor_dir :: proc(actor: ^Actor) -> vec3 {
	fwd, _, _: vec3 = actor_orientation(actor)
	return fwd
}

actor_orientation :: proc(actor: ^Actor) -> (fwd, left, up: vec3) {
	m: r.Matrix = actor.model.transform
	// right = {m.m0, m.m1, m.m2}     // First column
	left = vec3{m[0, 0], m[1, 0], m[2, 0]}
	// up = {m.m4, m.m5, m.m6}        // Second column
	up = vec3{m[0, 1], m[1, 1], m[2, 1]}
	// forward = {m.m8, m.m9, m.m10}  // Third column
	fwd = vec3{m[0, 2], m[1, 2], m[2, 2]}
	return
}


//actor states
input_dir :: proc() -> i32 {
	input_dir: i32
	if r.IsKeyDown(.W) {
		input_dir += 1
	}
	if r.IsKeyDown(.S) {
		input_dir -= 1
	}
	return input_dir
}

handle_idle :: proc() {
	play_anim(&actor.animator, .IDLE)
	turn()

	//state conditions	
	walk_cond := input_dir() != 0
	interact_tgr := get_interactable_colliding_actor(interactables[:], actor)
	interact_tgr_found := interact_tgr != {}
	interact_cond := r.IsKeyPressed(.E) && interact_tgr_found
	switch {
	case walk_cond:
		actor.state = .WALK
		fmt.println("handle_walk")
	case interact_cond:
		actor.state = .INTERACT
		fmt.println("handle_interact")
	}
}


handle_walk :: proc(dt: f32) {
	input_dir := f32(input_dir())
	play_anim(&actor.animator, input_dir == 0 ? .IDLE : .WALK)
	turn()
	desired_dpos: vec3 = input_dir * actor.speed * dt * actor_dir(&actor)
	dpos: vec3 = slide(desired_dpos)

	actor.pos += dpos
	actor.bounding_box_glob = r.BoundingBox {
		min = actor.bounding_box_glob.min + dpos,
		max = actor.bounding_box_glob.max + dpos,
	}

	// State transitions
	interact_tgr := get_interactable_colliding_actor(interactables[:], actor)
	interact_tgr_found := interact_tgr != {}
	interact_cond := interact_tgr_found && r.IsKeyPressed(.E)
	should_move := r.IsKeyDown(.W) || r.IsKeyDown(.S)
	is_moving := input_dir != 0
	idle_cond := !should_move && !is_moving
	switch {
	case interact_cond:
		actor.state = .INTERACT
		fmt.println("handle_interact")
	case idle_cond:
		actor.state = .IDLE
		fmt.println("handle_idle")
	}

	slide :: proc(desired_dpos: vec3) -> vec3 {
		remaining_dpos := desired_dpos
		max_slide_iterations :: 3
		dpos := vec3{0, 0, 0}

		for _ in 0 ..< max_slide_iterations {
			if remaining_dpos == {0, 0, 0} do break

			new_bb := r.BoundingBox {
				min = actor.bounding_box_glob.min + remaining_dpos,
				max = actor.bounding_box_glob.max + remaining_dpos,
			}

			if bounding_box_inside_walk_area(new_bb, walk_area_tris[:]) {
				dpos = remaining_dpos
				break
			}

			// Try moving X component
			rem_dpos_x := vec3{remaining_dpos.x, 0, 0}
			bb_x := r.BoundingBox {
				min = actor.bounding_box_glob.min + rem_dpos_x,
				max = actor.bounding_box_glob.max + rem_dpos_x,
			}

			// Try moving Z component
			rem_dpos_z := vec3{0, 0, remaining_dpos.z}
			bb_z := r.BoundingBox {
				min = actor.bounding_box_glob.min + rem_dpos_z,
				max = actor.bounding_box_glob.max + rem_dpos_z,
			}

			x_valid := bounding_box_inside_walk_area(bb_x, walk_area_tris[:])
			z_valid := bounding_box_inside_walk_area(bb_z, walk_area_tris[:])

			if x_valid && z_valid {
				dpos += remaining_dpos
				break
			} else if x_valid {
				dpos += rem_dpos_x
				remaining_dpos.z = 0
			} else if z_valid {
				dpos += rem_dpos_z
				remaining_dpos.x = 0
			} else {
				remaining_dpos *= 0.5
			}
		}

		return dpos
	}
}


handle_interact :: proc() {
	play_anim(&actor.animator, .INTERACT)
	
	//state conditions	
	walk_cond := last_frame_reached(&actor.animator) && input_dir() != 0
	idle_cond := last_frame_reached(&actor.animator)
	switch {
	case walk_cond:
		actor.state = .WALK
		fmt.println("handle_idle")
	case idle_cond:
		actor.state = .IDLE
		fmt.println("handle_idle")
	}
}


get_interactable_colliding_actor :: proc(
	interactables: []Interactable,
	actor: Actor,
) -> Interactable {
	for &intr in interactables {
		col := r.CheckCollisionBoxes(actor.bounding_box_glob, r.GetModelBoundingBox(intr.model))
		if (col) {
			return intr
		}
	}

	return {}
}
