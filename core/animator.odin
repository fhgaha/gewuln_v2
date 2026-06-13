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
    frame_idx := animator.anim_cur_frame
    animator.anim_cur_frame = (animator.anim_cur_frame + 1) % anim.frameCount
    neck_idx := int(actor.neck_bone_index)
    // Cache neck+children rotations (if neck exists)
    cached: map[int]r.Quaternion
    defer {
        for i, rot in cached {
            anim^.framePoses[frame_idx][i].rotation = rot
        }
        delete(cached)
    }
    if neck_idx != -1 {
        for i in 0 ..< int(actor.model.boneCount) {
            if i == neck_idx || is_child_of_neck(actor, i, neck_idx) {
                cached[i] = anim^.framePoses[frame_idx][i].rotation
            }
        }
    }
    // Determine target: identity unless looking at an interactable
    target := r.Quaternion(1)
    if neck_idx != -1 && len(cur_level().intersected_interactables) > 0 {
        ok, neck_local := get_bone_transform(&actor.model, neck_idx, anim^.framePoses[frame_idx])
        assert(ok, "cant get bone transform")
        neck_pos := neck_local.translation + actor.pos
        world_dir := r.Vector3Normalize(get_interactable_center(&cur_level().intersected_interactables[0]) - neck_pos)
        local_dir := r.Vector3Normalize(r.Vector3Transform(world_dir, r.MatrixRotateY(-actor.yaw)))
        angle_y := vec3_angle(vec3{local_dir.x, 0, local_dir.z}, FORWARD)
        if angle_y * r.RAD2DEG < ACTOR_NECK_MAX_YAW_DEG {
            if .show_gizmos in flags {
                draw_debug_line(neck_pos, get_interactable_center(&cur_level().intersected_interactables[0]), r.BEIGE)
            }
            target = neck_target_rotation(local_dir)
        }
    }
    // Slerp delta toward target (identity → smooth decay when not looking)
    actor.neck_current_delta = r.QuaternionSlerp(actor.neck_current_delta, target, 0.15)
    // Apply smoothed delta to cached bones
    for i, original_rot in cached {
        anim^.framePoses[frame_idx][i].rotation = actor.neck_current_delta * original_rot
    }
    r.UpdateModelAnimation(actor.model, anim^, frame_idx)
    // (defer) restore cached rotations and delete map
}

@(private = "file")
neck_target_rotation :: proc(local_dir: vec3) -> r.Quaternion {
    pitch := math.asin(clamp(local_dir.y, -1, 1))
    pitch = clamp(pitch, -ACTOR_NECK_MAX_PITCH_DEG * r.DEG2RAD, ACTOR_NECK_MAX_PITCH_DEG * r.DEG2RAD)
    horiz_len := math.sqrt(local_dir.x * local_dir.x + local_dir.z * local_dir.z)
    clamped_dir := local_dir
    if horiz_len > 0.001 {
        scale := math.cos(pitch) / horiz_len
        clamped_dir.x *= scale
        clamped_dir.z *= scale
    } else {
        clamped_dir.x = 0
        clamped_dir.z = math.cos(pitch)
    }
    clamped_dir.y = math.sin(pitch)
    lookat := r.MatrixInvert(r.MatrixLookAt(vec3{0, 0, 0}, -clamped_dir, UP))
    return r.QuaternionFromMatrix(lookat)
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
