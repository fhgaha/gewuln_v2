package core

import r "vendor:raylib"

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

