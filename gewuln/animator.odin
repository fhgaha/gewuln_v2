package gewuln

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
	return animator.anim_cur_frame == anim.frameCount - 1
}

fill_animation_names :: proc(animator: ^Animator) {
	for &a, i in animator.anims[:animator.anims_count] {
		name_cstr := cstring(&a.name[0])
		name_str := string(name_cstr)
		animator.anims_by_names[name_str] = i32(i)
		// fmt.println("+++ ", name_str, ": ", actor.anims_names[name_str])
	}
}

play_anim :: proc(
	animator: ^Animator,
	state: Actor_State_Type,
) {
	name: string = Actor_State_Type_strings[state]
	already_playing := animator.anim_idx == animator.anims_by_names[name]
	if already_playing {
		return
	}
	animator.anim_idx = animator.anims_by_names[name]
	animator.anim_cur_frame = 0
}

actor_anim_update :: proc(actor: ^Actor) {
	animator := &actor.animator
	anim := &animator.anims[animator.anim_idx]
	frame_idx := animator.anim_cur_frame

	animator.anim_cur_frame = (animator.anim_cur_frame + 1) % anim.frameCount

	// Cache neck+children rotations (if neck exists)
	cached: map[int]r.Quaternion
	defer {
		for i, cashed_rot in cached {
			anim^.framePoses[frame_idx][i].rotation = cashed_rot
		}
		delete(cached)
	}

	if main_actor_ctx.rotate_neck_while_looking_at_intr {
		rotate_neck(actor, &cached)
	}

	r.UpdateModelAnimation(actor.model, anim^, frame_idx)
	// (defer) restore cached rotations and delete map
}

@(private = "file")
rotate_neck :: proc(actor: ^Actor, cached: ^map[int]r.Quaternion) {
	animator := &actor.animator
	anim := &animator.anims[animator.anim_idx]
	frame_idx := animator.anim_cur_frame

	target_dir_quat := r.Quaternion(1)
	is_looking: bool
	neck_idx := int(actor.neck_bone_index)

	if neck_idx != -1 {
		// cash neck child bones
		for i in 0 ..< int(actor.model.boneCount) {
			if i == neck_idx || is_child_of_neck(actor, i, neck_idx) {
				cached[i] = anim^.framePoses[frame_idx][i].rotation
			}
		}

		if len(main_actor_ctx.intersected_interactables) > 0 {
			target_dir_quat, is_looking = actor_is_looking_at_point(
				actor,
				get_interactable_center(main_actor_ctx.intersected_interactables[0]),
			)
		}

		// Slerp delta toward target (identity → smooth decay when not looking)
		actor.neck_current_delta = r.QuaternionSlerp(
			actor.neck_current_delta,
			target_dir_quat,
			0.15,
		)

		// Apply smoothed delta to cached bones
		for i, original_rot in cached {
			anim^.framePoses[frame_idx][i].rotation = actor.neck_current_delta * original_rot
		}
	}
}

@(private = "file")
is_child_of_neck :: proc(actor: ^Actor, bone_index: int, target_parent_index: int) -> bool {
	current_parent := actor.model.bones[bone_index].parent

	for current_parent != -1 {
		if int(current_parent) == target_parent_index do return true
		current_parent = actor.model.bones[current_parent].parent
	}
	return false
}
