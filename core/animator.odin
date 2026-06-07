package core

import "core:math"
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

play_anim :: proc(animator: ^Animator, state: Actor_State) {
	name: string = actor_state_strings[state]
	already_playing := animator.anim_idx == animator.anims_by_names[name]
	if already_playing {
		return
	}
	animator.anim_idx = animator.anims_by_names[name]
	animator.anim_cur_frame = 0
}


actor_anim_update :: proc(actor: ^Actor) {
	animator: ^Animator = &actor.animator
	anim := &animator.anims[animator.anim_idx]

	// 1. Advance the frame counter EXACTLY ONCE per update step
	animator.anim_cur_frame = (animator.anim_cur_frame + 1) % anim.frameCount

	// 2. Manipulate the targeted skeleton tracks locally using our active frame index
	// No target position needed anymore!
	rotate_neck(actor, animator.anim_cur_frame)

	// 3. Process the fully adjusted animation frame matrices down to the GPU
	r.UpdateModelAnimation(actor.model, anim^, animator.anim_cur_frame)
}

rotate_neck :: proc(actor: ^Actor, frame_idx: i32) {
	if actor.neck_bone_index == -1 do return

	animator := &actor.animator
	anim := &animator.anims[animator.anim_idx]
	neck_idx := int(actor.neck_bone_index)

	// 1. Calculate a dynamic rotation angle spinning cleanly over time
	angle := f32(r.GetTime() * 2.0)

	// 2. Generate a clean rotation quaternion around the Z axis (Roll)
	custom_rotation := r.QuaternionFromEuler(0, 0, angle)

	// 3. Loop through the skeleton to apply the rotation to the neck and all child bones
	for i in 0 ..< int(actor.model.boneCount) {
		if i == neck_idx {
			original_rot := anim^.framePoses[frame_idx][i].rotation
			// Custom rotation on the LEFT acts as a smooth parent space offset
			anim^.framePoses[frame_idx][i].rotation = custom_rotation * original_rot
			
		} else if is_child_of_neck(actor, i, neck_idx) {
			original_rot := anim^.framePoses[frame_idx][i].rotation
			// Custom rotation on the LEFT ensures children (head/eyes) turn with the neck
			anim^.framePoses[frame_idx][i].rotation = custom_rotation * original_rot
		}
	}
}






// Keeping this as a clean structural nested proc context boundary utility
is_child_of_neck :: proc(actor: ^Actor, bone_index: int, target_parent_index: int) -> bool {
	current_parent := actor.model.bones[bone_index].parent

	for current_parent != -1 {
		if int(current_parent) == target_parent_index do return true
		current_parent = actor.model.bones[current_parent].parent
	}
	return false
}
