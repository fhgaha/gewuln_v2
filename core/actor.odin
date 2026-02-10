package core

import "core:fmt"
import r "vendor:raylib"

Actor :: struct {
	pos:                   vec3,
	speed, rot_speed:      f32,
	model:                 r.Model,
	bounding_box_original: r.BoundingBox,
	bounding_box:          r.BoundingBox,
	state:                 Actor_State,
	animator:              Animator,
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

Input_State :: struct {
	move_dir:       f32, // -1 to 1 (Forward/Back)
	turn_dir:       f32, // -1 to 1 (Left/Right)
	wants_interact: bool,
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
		bounding_box_original = bb,
		bounding_box = bb,
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

handle_idle :: proc(dt: f32) {
	rotation_amount := input.turn_dir * actor.rot_speed * dt
	actor.model.transform *= r.MatrixRotateY(rotation_amount)

	play_anim(&actor.animator, .IDLE)

	// state transitions	
	walk_cond := input.move_dir != 0
	interact_tgr, interact_tgr_found := get_interactable_colliding_actor(interactables[:], actor)
	interact_cond := input.wants_interact && interact_tgr_found
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
	rotation_amount := input.turn_dir * actor.rot_speed * dt
	actor.model.transform *= r.MatrixRotateY(rotation_amount)

	play_anim(&actor.animator, .WALK)

	desired_dpos: vec3 = input.move_dir * actor.speed * dt * actor_dir(&actor)
	dpos := resolve_slide(desired_dpos, actor.bounding_box, walk_area_tris[:])
	actor.pos += dpos
	actor.bounding_box.min += dpos
	actor.bounding_box.max += dpos

	// state transitions
	interact_tgr, interact_tgr_found := get_interactable_colliding_actor(interactables[:], actor)
	interact_cond := interact_tgr_found && input.wants_interact
	idle_cond := input.move_dir == 0
	switch {
	case interact_cond:
		actor.state = .INTERACT
		fmt.println("handle_interact")
	case idle_cond:
		actor.state = .IDLE
		fmt.println("handle_idle")
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
	play_anim(&actor.animator, .INTERACT)

	//state conditions	
	walk_cond := last_frame_reached(&actor.animator) && input.move_dir != 0
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
) -> (
	interactable: Interactable,
	found: bool,
) {
	for &intr in interactables {
		col := r.CheckCollisionBoxes(actor.bounding_box, r.GetModelBoundingBox(intr.model))
		if (col) {
			return intr, true
		}
	}

	return {}, false
}
