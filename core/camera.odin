package core

import "core:math"
//raylib UpdateCamera src:  https://github.com/raysan5/raylib/blob/5b0a799769da9a2ebc662d4aab1f31cf85882c56/src/rcamera.h#L445
import r "vendor:raylib"

update_cam :: proc(dt: f32) {
	switch {
	case .camera_debug in flags:
		update_cam_debug(dt)
	case .camera_follow in flags:
		update_cam_follow(dt)
	}
}

update_cam_debug :: proc(dt: f32) {
	//free camera with moving on arrows

	cam_speed: f32 = 10

	cam := &cur_level().cam

	if r.IsKeyDown(.UP) { 	//forward
		r.CameraMoveForward(cam, cam_speed * dt, moveInWorldPlane = false)
	}
	if r.IsKeyDown(.DOWN) { 	//backward
		r.CameraMoveForward(cam, -cam_speed * dt, moveInWorldPlane = false)
		// r.CameraMoveToTarget(cam, cam_speed * dt);
	}
	if r.IsKeyDown(.LEFT) {
		r.CameraMoveRight(cam, -cam_speed * dt, moveInWorldPlane = false)
	}
	if r.IsKeyDown(.RIGHT) {
		r.CameraMoveRight(cam, cam_speed * dt, moveInWorldPlane = false)
	}

	//rotations
	//pitch, yaw, roll -> тангаж, курс, крен
	cam_rot_speed: f32 = 0.1
	mouse_pos_delta: vec2 = r.GetMouseDelta()

	if .lock_cursor in flags {
		//тангаж
		r.CameraPitch(
			cam,
			-mouse_pos_delta.y * cam_rot_speed * dt,
			lockView = false,
			rotateAroundTarget = false,
			rotateUp = false,
		)
		//курс
		r.CameraYaw(cam, -mouse_pos_delta.x * cam_rot_speed * dt, rotateAroundTarget = true)
	}
	r.CameraMoveToTarget(cam, -r.GetMouseWheelMove()) //zoom
}

Third_Person_Cam :: struct {
	distance:     f32,
	height:       f32,
	smooth_speed: f32,
}

// Add to Level struct or config
default_third_person_cam := Third_Person_Cam {
	distance     = 4.0,
	height       = 1.8,
	smooth_speed = 5.0,
}

update_cam_follow :: proc(dt: f32, cam_cfg: Third_Person_Cam = default_third_person_cam) {
	cam := &cur_level().cam
	// player_pos := cur_level().actor.pos
	// player_yaw := cur_level().actor.yaw
	player_pos := main_actor.pos
	player_yaw := main_actor.yaw


	// Calculate offset behind player (opposite to facing direction)
	offset_x := -math.sin(player_yaw) * cam_cfg.distance
	offset_z := -math.cos(player_yaw) * cam_cfg.distance

	target_pos := vec3 {
		player_pos.x + offset_x,
		player_pos.y + cam_cfg.height,
		player_pos.z + offset_z,
	}
	// Smooth follow with lerp
	t := cam_cfg.smooth_speed * dt
	cam.position = vec3_lerp(cam.position, target_pos, t)

	// Target is player's position (slightly above ground)
	cam.target = vec3{player_pos.x, player_pos.y + 1.0, player_pos.z}
}
