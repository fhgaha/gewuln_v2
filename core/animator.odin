package core

import "core:math"
import "core:math/linalg"
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

	if len(cur_level().intersected_intractables) > 0 {
		// cash neck and its children bone rotations
		cached: map[int]r.Quaternion
		defer delete(cached)
		for i in 0 ..< int(actor.model.boneCount) {
			if i == neck_idx || is_child_of_neck(actor, i, neck_idx) {
				cached[i] = anim^.framePoses[frame_idx][i].rotation
			}
		}

		interactable_pos := get_interactable_center(&cur_level().intersected_intractables[0])
		rotate_neck(actor, interactable_pos)
		r.UpdateModelAnimation(actor.model, anim^, animator.anim_cur_frame)

		// restore cashed neck and children bone rotations
		for i, rot in cached {
			anim^.framePoses[frame_idx][i].rotation = rot
		}
	} else {
		r.UpdateModelAnimation(actor.model, anim^, animator.anim_cur_frame)
	}
}


// rotate_neck :: proc(actor: ^Actor, interactable_pos: vec3) {
// 	if actor.neck_bone_index == -1 do return

// 	animator := &actor.animator
// 	anim := &animator.anims[animator.anim_idx]
// 	neck_idx := int(actor.neck_bone_index)
// 	frame_idx := animator.anim_cur_frame

// 	neck_pos := vec3{actor.pos.x, 1.7, actor.pos.z}

// 	look_mat :=
// 		r.MatrixInvert(r.MatrixLookAt(neck_pos, interactable_pos, UP)) *
// 		r.MatrixRotateY(r.PI - actor.yaw)
// 	draw_debug_line(neck_pos, interactable_pos, r.BEIGE)

// 	/*
// 	A 4x4 transform matrix in raylib (column-major) looks like:
// 	[ Rx  Ux  Fx  Tx ]    R = right    (X basis)
// 	[ Ry  Uy  Fy  Ty ]    U = up       (Y basis)
// 	[ Rz  Uz  Fz  Tz ]    F = forward  (Z basis)
// 	[  0   0   0   1 ]    T = translation
// 	- Column 3 (Tx, Ty, Tz): translation/position
// 	- Columns 0-2 (R, U, F): the 3x3 rotation/scale basis. For pure rotation, each column is unit length and orthogonal. For scale, length > 1.
// 	- Bottom row is always [0, 0, 0, 1] for affine transforms.
// 	*/

// 	// 2. Generate a clean rotation quaternion around the Z axis (Roll)
// 	custom_rotation := r.QuaternionFromMatrix(look_mat)
// 	// 3. Loop through the skeleton to apply the rotation to the neck and all child bones
// 	for i in 0 ..< int(actor.model.boneCount) {
// 		if i == neck_idx {
// 			original_rot := anim^.framePoses[frame_idx][i].rotation
// 			// Custom rotation on the LEFT acts as a smooth parent space offset
// 			anim^.framePoses[frame_idx][i].rotation = custom_rotation * original_rot

// 		} else if is_child_of_neck(actor, i, neck_idx) {
// 			original_rot := anim^.framePoses[frame_idx][i].rotation
// 			// Custom rotation on the LEFT ensures children (head/eyes) turn with the neck
// 			anim^.framePoses[frame_idx][i].rotation = custom_rotation * original_rot
// 		}
// 	}
// }

rotate_neck :: proc(actor: ^Actor, interactable_pos: vec3) {
    if actor.neck_bone_index == -1 do return
    animator := &actor.animator
    anim := &animator.anims[animator.anim_idx]
    neck_idx := int(actor.neck_bone_index)
    frame_idx := animator.anim_cur_frame
    neck_pos := vec3{actor.pos.x, 1.7, actor.pos.z}
    draw_debug_line(neck_pos, interactable_pos, r.BEIGE)
    // World-space direction from neck to target
    world_dir := r.Vector3Normalize(interactable_pos - neck_pos)
    // Transform world direction -> model space
    // Model transform is MatrixRotateY(yaw), so inverse is MatrixRotateY(-yaw)
    c := math.cos(actor.yaw)
    s := math.sin(actor.yaw)
    local_dir := vec3{
        world_dir.x * c - world_dir.z * s,
        world_dir.y,
        world_dir.x * s + world_dir.z * c,
    }
    local_dir = r.Vector3Normalize(local_dir)
    // Shortest-path rotation from model +Z to target direction
    FWD :: vec3{0, 0, 1}
    cross := r.Vector3CrossProduct(FWD, local_dir)
    len := r.Vector3Length(cross)
    neck_rotation: r.Quaternion
    if len > 0.0001 {
        cross /= len
        dot := math.clamp(r.Vector3DotProduct(FWD, local_dir), -1, 1)
        neck_rotation = r.QuaternionFromAxisAngle(cross, math.acos(dot))
    }
    for i in 0 ..< int(actor.model.boneCount) {
        if i == neck_idx || is_child_of_neck(actor, i, neck_idx) {
            original_rot := anim^.framePoses[frame_idx][i].rotation
            anim^.framePoses[frame_idx][i].rotation = neck_rotation * original_rot
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
