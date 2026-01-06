package core

import "core:fmt"
import "core:strconv"
import r "vendor:raylib"

Cam_Follow :: struct {
	cam:    r.Camera3D,
	target: vec3,
}

VIRTUAL_SCREEN_WIDTH :: 160
VIRTUAL_SCREEN_HEIGHT :: 90

VIRTUAL_RATIO :: f32(SCREEN_WIDTH) / f32(VIRTUAL_SCREEN_WIDTH)

font: r.Font
cam: r.Camera3D
cam_mode: r.CameraMode

Model :: struct {
	model:          r.Model,
	pos:            vec3,
	bounding_box:   r.BoundingBox,
	direction:      vec3,
	//animations
	anims_count:    i32,
	anim_idx:       i32,
	anim_cur_frame: i32,
	anims:          [^]r.ModelAnimation,
}

main :: proc() {

	//this raylib setup should be in top for some reason
	r.InitWindow(SCREEN_WIDTH, SCREEN_HEIGHT, "ogewuln")
	r.SetTraceLogLevel(.ALL)
	r.SetConfigFlags({.VSYNC_HINT})
	r.SetTargetFPS(60)
	r.DisableCursor()

	font = r.LoadFont("assets/centurygothic/centurygothic_bold.ttf")
	r.SetTextureFilter(font.texture, .BILINEAR)

	//set up
	cam = r.Camera3D {
		position   = vec3{0, 2, 2},
		target     = vec3{0, 1, 0},
		up         = vec3{0, 1, 0},
		fovy       = FOV_DEG / 2,
		projection = .PERSPECTIVE,
	}
	cam_mode = r.CameraMode.CUSTOM

	//model
	// model_path: cstring = "assets/models/robot/robot.glb"

	model_path: cstring = "assets/models/mona_sax/export/glb/mona.glb"
	collider_path: cstring = "assets/models/mona_sax/export/glb/collider.glb"
	anims_count: i32 = 0
	model := Model {
		model          = r.LoadModel(model_path),
		pos            = vec3{0, 0, 0},
		bounding_box   = r.GetModelBoundingBox(r.LoadModel(collider_path)),
		direction      = vec3{0, 0, -1},
		anims_count    = 0,
		anim_idx       = 0,
		anim_cur_frame = 0,
		anims          = r.LoadModelAnimations(model_path, &anims_count),
	}

	for !r.WindowShouldClose() {
		//update

		// switch {
		// case r.IsMouseButtonPressed(.RIGHT):
		// 	anim_idx = (anim_idx + 1) % anims_count
		// case r.IsMouseButtonPressed(.LEFT):
		// 	anim_idx = (anim_idx + anims_count - 1) % anims_count
		// }

		update_model_anim(&model)

		r.UpdateCamera(&cam, cam_mode)

		r.BeginDrawing()
		{
			r.ClearBackground(DARK)

			r.BeginMode3D(cam)
			{
				r.DrawModel(model.model, model.pos, 1, r.WHITE)
				r.DrawModelWires(model.model, model.pos, 1, r.WHITE)

				r.DrawGrid(slices = 10, spacing = 1)
				draw_gizmo()
			}
			r.EndMode3D()

			draw_fps()
		}
		r.EndDrawing()

		free_all(context.temp_allocator)
	}

	r.UnloadModelAnimations(model.anims, model.anims_count)
	r.UnloadModel(model.model)
	r.UnloadFont(font)

	r.CloseWindow()
}

// move_model: proc(model: Og_Model){

// }

update_model_anim :: proc(m: ^Model) {
	anim := m.anims[m.anim_idx]
	m.anim_cur_frame = (m.anim_cur_frame + 1) % anim.frameCount
	r.UpdateModelAnimation(m.model, anim, m.anim_cur_frame)
}


draw_gizmo :: proc() {
	dist := r.Vector3Distance(cam.position, vec3{0, 0, 0})
	r.DrawLine3D(vec3{0, 0, 0}, vec3{1, 0, 0} * dist, r.RED)
	r.DrawLine3D(vec3{0, 0, 0}, vec3{0, 1, 0} * dist, r.GREEN)
	r.DrawLine3D(vec3{0, 0, 0}, vec3{0, 0, 1} * dist, r.BLUE)
}

draw_fps :: proc() {
	r.DrawTextEx(
		font,
		text = r.TextFormat("FPS: %d", r.GetFPS()),
		position = 0,
		fontSize = 36,
		spacing = 0,
		tint = r.ORANGE,
	)
}
