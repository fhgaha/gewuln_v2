package core

import "core:fmt"
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
	animator := &actor.animator
	anim := &animator.anims[animator.anim_idx]
	animator.anim_cur_frame = (animator.anim_cur_frame + 1) % anim.frameCount
	frame_idx := animator.anim_cur_frame
	neck_idx := int(actor.neck_bone_index)


	if len(cur_level().intersected_interactables) > 0 {
		ok, neck_transform_local := get_bone_transform(
			&actor.model,
			neck_idx,
			anim^.framePoses[frame_idx],
		)
		assert(ok, "cant get bone transform")

		interactable_pos := get_interactable_center(&cur_level().intersected_interactables[0])
		world_neck_pos := neck_transform_local.translation + actor.pos
		world_dir := r.Vector3Normalize(interactable_pos - world_neck_pos)
		local_dir := r.Vector3Normalize(r.Vector3Transform(world_dir, r.MatrixRotateY(-actor.yaw)))
		angle_y := vec3_angle(vec3{local_dir.x, 0, local_dir.z}, FORWARD)
		actor_is_looking_at_interactable := angle_y * r.RAD2DEG < ACTOR_NECK_MAX_YAW_DEG

		if actor_is_looking_at_interactable {
			// cash neck and its children bone rotations
			cached: map[int]r.Quaternion
			defer delete(cached)
			for i in 0 ..< int(actor.model.boneCount) {
				if i == neck_idx || is_child_of_neck(actor, i, neck_idx) {
					cached[i] = anim^.framePoses[frame_idx][i].rotation
				}
			}

			interactable_pos := get_interactable_center(&cur_level().intersected_interactables[0])
			rotate_neck(actor, interactable_pos)
			r.UpdateModelAnimation(actor.model, anim^, animator.anim_cur_frame)

			// restore cashed neck and children bone rotations
			for i, rot in cached {
				anim^.framePoses[frame_idx][i].rotation = rot
			}
		} else {
			r.UpdateModelAnimation(actor.model, anim^, animator.anim_cur_frame)
		}
	} else {
		r.UpdateModelAnimation(actor.model, anim^, animator.anim_cur_frame)
	}
}

@(private = "file")
rotate_neck :: proc(actor: ^Actor, interactable_pos: vec3) {
	// actor has no neck
	if actor.neck_bone_index == -1 do return

	animator := &actor.animator
	anim := &animator.anims[animator.anim_idx]
	neck_idx := int(actor.neck_bone_index)
	frame_idx := animator.anim_cur_frame

	ok, neck_pos_local := get_bone_transform(&actor.model, neck_idx, anim^.framePoses[frame_idx])
	assert(ok, "cant get bone transform")
	world_neck_pos := neck_pos_local.translation + actor.pos

	if .show_gizmos in flags {
		draw_debug_line(world_neck_pos, interactable_pos, r.BEIGE)
	}

	// Direction from neck to interactable, does not depend on actor's yaw
	world_dir := r.Vector3Normalize(interactable_pos - world_neck_pos)
	// The character can be rotated by `actor.yaw`. Bones in the animation are in
	// the model's own local space, so we "undo" the yaw to get the correct local direction.
	// MatrixRotateY(-actor.yaw) rotates the vector backward by the character's facing angle.
	// This changes when the character rotates
	local_dir := r.Vector3Normalize(r.Vector3Transform(world_dir, r.MatrixRotateY(-actor.yaw)))

	// Limit pitch. Actor keeps looking at the target but head does not pitch too much.
	pitch := math.asin(clamp(local_dir.y, -1, 1))
	pitch = clamp(
		pitch,
		-ACTOR_NECK_MAX_PITCH_DEG * r.DEG2RAD,
		ACTOR_NECK_MAX_PITCH_DEG * r.DEG2RAD,
	)
	// Reconstruct direction: preserve horizontal (yaw) direction, apply clamped pitch
	horiz_len := math.sqrt(local_dir.x * local_dir.x + local_dir.z * local_dir.z)
	if horiz_len > 0.001 {
		scale := math.cos(pitch) / horiz_len
		local_dir.x *= scale
		local_dir.z *= scale
	} else {
		// Vertical edge case — pick forward (+Z) as default horizontal
		local_dir.x = 0
		local_dir.z = math.cos(pitch)
	}
	local_dir.y = math.sin(pitch)


	// MatrixLookAt looks along -Z, so we use -local_dir as the target.
	// That makes +Z (the bone's default forward) point toward our target.
	// We invert it because LookAt produces a view matrix; we want the object rotation.
	lookat := r.MatrixInvert(r.MatrixLookAt(vec3{0, 0, 0}, -local_dir, UP))
	neck_rotation := r.QuaternionFromMatrix(lookat)

	for i in 0 ..< int(actor.model.boneCount) {
		if i == neck_idx || is_child_of_neck(actor, i, neck_idx) {
			anim^.framePoses[frame_idx][i].rotation =
				neck_rotation * anim^.framePoses[frame_idx][i].rotation
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
