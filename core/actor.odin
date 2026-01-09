package core

import r "vendor:raylib"

Actor :: struct {
	pos:              vec3,
	dir:              vec3,
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

Animator :: struct {
	anims_count, anim_idx, anim_cur_frame: i32,
	anims:                                 [^]r.ModelAnimation, //ptr to array
	anims_names:                           map[string]i32,
}

last_frame_reached :: proc(animator: ^Animator) -> bool {
	anim := animator.anims[animator.anim_idx]
	return (animator.anim_cur_frame + 1) == anim.frameCount
}

fill_animation_names :: proc(animator: ^Animator) {
	for &a, i in animator.anims[:animator.anims_count] {
		name_cstr := cstring(&a.name[0])
		name_str := string(name_cstr)
		animator.anims_names[name_str] = i32(i)
		// fmt.println("+++ ", name_str, ": ", actor.anims_names[name_str])
	}
}

play_anim :: proc(animator: ^Animator, name: string) {
	animator.anim_idx = animator.anims_names[name]
}

update_model_anim :: proc(actor: ^Actor) {
	animator := &actor.animator
	anim := animator.anims[animator.anim_idx]
	animator.anim_cur_frame = (animator.anim_cur_frame + 1) % anim.frameCount
	r.UpdateModelAnimation(actor.model, anim, animator.anim_cur_frame)
}
