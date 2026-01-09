package core

import r "vendor:raylib"

Actor :: struct {
	speed, rot_speed: f32,
	model:            r.Model,
	bounding_box:     r.BoundingBox,
	state:            Actor_State,
	animator:         Animator,
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
	if !r.IsModelValid(actor_model) { 	// You'd need a check
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

	// Assemble the actor
	actor^ = Actor {
		speed = 2,
		rot_speed = 4,
		model = actor_model,
		bounding_box = r.GetModelBoundingBox(actor_coll_model),
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

to_vec4 :: proc(v: vec3) -> vec4 {
	return vec4{v.x, v.y, v.z, 1}
}

to_vec3 :: proc(v: vec4) -> vec3 {
	return vec3{v.x, v.y, v.z}
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

update_model_anim :: proc(actor: ^Actor) {
	animator: ^Animator = &actor.animator
	anim: r.ModelAnimation = animator.anims[animator.anim_idx]
	animator.anim_cur_frame = (animator.anim_cur_frame + 1) % anim.frameCount
	r.UpdateModelAnimation(actor.model, anim, animator.anim_cur_frame)
}
