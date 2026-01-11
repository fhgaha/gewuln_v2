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
	m: r.Matrix = actor.model.transform
	return vec3{m[0, 3], m[1, 3], m[2, 3]}
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
	input_dir := input_dir()
	walk_cond := input_dir != 0
	interact_cond := r.IsKeyPressed(.E)
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
	play_anim(&actor.animator, .WALK)
	turn()
	input_dir := f32(input_dir()) //-1, 0 or 1
	// vel: vec3 = input_dir * actor.speed * dt * FORWARD
	vel: vec3 = input_dir * actor.speed * dt * actor_dir(&actor)
	
	new_bb := r.BoundingBox{
		min = actor.bounding_box_glob.min + vel,
		max = actor.bounding_box_glob.max + vel
	}
	inside_walk_area := bounding_box_inside_walk_area(new_bb, walk_area_tris[:])
	if inside_walk_area{
		actor.pos += vel
		actor.bounding_box_glob = new_bb
	}

	// fmt.println("vel len: ", r.Vector3Length(velocity))
	should_move := r.IsKeyDown(.W) || r.IsKeyDown(.S)
	is_moving := r.Vector3Length(vel) != 0
	idle_cond := !should_move && !is_moving
	if idle_cond {
		actor.state = .IDLE
		fmt.println("handle_idle")
	}
	interact_cond := r.IsKeyPressed(.E)
	if interact_cond {
		actor.state = .INTERACT
		fmt.println("handle_interact")
	}
}

handle_interact :: proc() {
	play_anim(&actor.animator, .INTERACT)
	idle_cond := last_frame_reached(&actor.animator)
	if idle_cond {
		actor.state = .IDLE
		fmt.println("handle_idle")
	}
}


//animations
Animator :: struct {
	anims_count:    i32, //amount of animations
	anim_idx:       i32, //index of current animation
	anim_cur_frame: i32, //current frame of current animation
	anims:          [^]r.ModelAnimation, //ptr to array
	anims_by_names: map[string]i32, //aniamtion names mapped to anim_idx
}

last_frame_reached :: proc(animator: ^Animator) -> bool {
	anim := animator.anims[animator.anim_idx]
	return (animator.anim_cur_frame + 1) == anim.frameCount
}

fill_animation_names :: proc(animator: ^Animator) {
	for &a, i in animator.anims[:animator.anims_count] {
		name_cstr := cstring(&a.name[0])
		name_str := string(name_cstr)
		animator.anims_by_names[name_str] = i32(i)
		// fmt.println("+++ ", name_str, ": ", actor.anims_names[name_str])
	}
}

play_anim :: proc(animator: ^Animator, state: Actor_State) {
	name: string = actor_state_strings[state]
	already_playing := animator.anim_idx == animator.anims_by_names[name]
	if already_playing {
		return
	}
	animator.anim_idx = animator.anims_by_names[name]
	animator.anim_cur_frame = 0
}

update_actor_anim :: proc(actor: ^Actor) {
	animator: ^Animator = &actor.animator
	anim: r.ModelAnimation = animator.anims[animator.anim_idx]
	animator.anim_cur_frame = (animator.anim_cur_frame + 1) % anim.frameCount
	r.UpdateModelAnimation(actor.model, anim, animator.anim_cur_frame)
}
