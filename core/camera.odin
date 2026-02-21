package core

//raylib UpdateCamera src:  https://github.com/raysan5/raylib/blob/5b0a799769da9a2ebc662d4aab1f31cf85882c56/src/rcamera.h#L445
import r "vendor:raylib"

update_cam :: proc(dt: f32) {
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
