package core

import "core:fmt"
import r "vendor:raylib"

VIRTUAL_SCREEN_WIDTH :: 160
VIRTUAL_SCREEN_HEIGHT :: 90

VIRTUAL_RATIO :: f32(SCREEN_WIDTH) / f32(VIRTUAL_SCREEN_WIDTH)

cam: r.Camera3D
cam_mode: r.CameraMode

main :: proc() {

	//this raylib setup should be in top for some reason
	r.InitWindow(SCREEN_WIDTH, SCREEN_HEIGHT, "ogewuln")
	r.SetTraceLogLevel(.ALL)
	r.SetConfigFlags({.VSYNC_HINT})
	r.SetTargetFPS(60)
	r.DisableCursor()

	font: r.Font = r.LoadFont("assets/centurygothic/centurygothic_bold.ttf")
	r.SetTextureFilter(font.texture, .BILINEAR)

	//set up
	cam = r.Camera3D {
		position   = vec3{0, 10, 10},
		target     = vec3{0, 1, 0},
		up         = vec3{0, 1, 0},
		fovy       = FOV_DEG / 2,
		projection = .PERSPECTIVE,
	}
	cam_mode = r.CameraMode.THIRD_PERSON

	//model
	model_path: cstring = "assets/models/mona_sax/export/glb/mona.glb"
	model: r.Model = r.LoadModel(model_path)
	model_pos := vec3{0, 0, 0}
	anims_count: i32 = 0
	anim_idx: i32 = 0
	anim_cur_frame: i32 = 0
	model_animations := r.LoadModelAnimations(model_path, &anims_count)


	for !r.WindowShouldClose() {
		//update

		// if r.IsMouseButtonPressed(.RIGHT) {
		// 	anim_idx = (anim_idx + 1) % anims_count
		// } else if r.IsMouseButtonPressed(.LEFT) {
		// 	anim_idx = (anim_idx + anims_count - 1) % anims_count
		// }

		anim := model_animations[anim_idx]
		anim_cur_frame = (anim_cur_frame + 1) % anim.frameCount
		r.UpdateModelAnimation(model, anim, anim_cur_frame)

		r.UpdateCamera(&cam, cam_mode)

		r.BeginDrawing()
		{
			r.ClearBackground(DARK)

			r.BeginMode3D(cam)
			{
				r.DrawCubeWires(
					position = vec3{0, 0.5, 0},
					width = 1,
					height = 1,
					length = 1,
					color = r.RED,
				)
				r.DrawModel(model, model_pos, 1, r.WHITE)
				// r.DrawModelWires(model, model_pos, 1, r.GREEN)
				// r.DrawBoundingBox(r.GetModelBoundingBox(model), r.RED)

				r.DrawGrid(slices = 10, spacing = 1)
				draw_gizmo()
			}
			r.EndMode3D()

			r.DrawTextEx(
				font,
				text = r.TextFormat("FPS: %d", r.GetFPS()),
				position = 0,
				fontSize = 36,
				spacing = 0,
				tint = r.ORANGE,
			)
		}
		r.EndDrawing()
	}

	r.UnloadModel(model)
	r.UnloadModelAnimations(model_animations, anims_count)

	r.UnloadFont(font)
	r.CloseWindow()
}


draw_gizmo :: proc() {
	dist := r.Vector3Distance(cam.position, vec3{0, 0, 0})
	r.DrawLine3D(vec3{0, 0, 0}, vec3{1, 0, 0} * dist, r.RED)
	r.DrawLine3D(vec3{0, 0, 0}, vec3{0, 1, 0} * dist, r.GREEN)
	r.DrawLine3D(vec3{0, 0, 0}, vec3{0, 0, 1} * dist, r.BLUE)
}

foo :: proc() {
	fmt.println("test")
}
