package core

import "core:fmt"
import "core:strconv"
import "core:strings"
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

Actor :: struct {
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

	font = r.LoadFont("assets/fonts/centurygothic/centurygothic_bold.ttf")
	r.SetTextureFilter(font.texture, .BILINEAR)
	defer r.UnloadFont(font)

	//set up
	cam = r.Camera3D {
		position   = vec3{0, 2, 2},
		target     = vec3{0, 1, 0},
		up         = vec3{0, 1, 0},
		fovy       = FOV_DEG / 2,
		projection = .PERSPECTIVE,
	}
	cam_mode = r.CameraMode.FREE

	//actor
	// model_path: cstring = "assets/models/robot/robot.glb"
	actor_path: cstring = "assets/models/mona_sax/export/glb/mona.glb"
	collider_path: cstring = "assets/models/mona_sax/export/glb/collider.glb"
	actor := Actor {
		model          = r.LoadModel(actor_path),
		pos            = vec3{0, 0, 0},
		bounding_box   = r.GetModelBoundingBox(r.LoadModel(collider_path)),
		direction      = vec3{0, 0, -1},
		anims_count    = 0,
		anim_idx       = 0,
		anim_cur_frame = 0,
	}
	actor.anims = r.LoadModelAnimations(actor_path, &actor.anims_count)
	defer r.UnloadModelAnimations(actor.anims, actor.anims_count)
	defer r.UnloadModel(actor.model)

	//room
	room_path: cstring = "assets/models/test_rooms/export/test_floor/gltf_4_two_interactables_one_with_center_below_another_with_center_above/test_rooms.gltf"
	room := r.LoadModel(room_path)
	defer r.UnloadModel(room)

	// for &a in model.anims[:model.anims_count] {
	// 	str := string(a.name[:])
	// 	fmt.println("++ ", str)
	// }


	for !r.WindowShouldClose() {
		//update

		switch {
		case r.IsMouseButtonPressed(.RIGHT):
			actor.anim_idx = (actor.anim_idx + 1) % actor.anims_count
		case r.IsMouseButtonPressed(.LEFT):
			actor.anim_idx = (actor.anim_idx + actor.anims_count - 1) % actor.anims_count
		}

		update_model_anim(&actor)

		r.UpdateCamera(&cam, cam_mode)

		r.BeginDrawing()
		{
			r.ClearBackground(DARK)

			r.BeginMode3D(cam)
			{
				r.DrawModel(room, vec3{0, 0, 0}, 1, r.WHITE)
				r.DrawModel(actor.model, actor.pos, 1, r.WHITE)
				r.DrawModelWires(actor.model, actor.pos, 1, r.WHITE)
				r.DrawBoundingBox(actor.bounding_box, r.MAGENTA)

				// r.DrawGrid(slices = 10, spacing = 1)
				draw_gizmo()
			}
			r.EndMode3D()

			draw_fps()
		}
		r.EndDrawing()

		free_all(context.temp_allocator)
	}


	r.CloseWindow()
}

// move_model: proc(model: Og_Model){

// }

update_model_anim :: proc(actor: ^Actor) {
	anim := actor.anims[actor.anim_idx]
	actor.anim_cur_frame = (actor.anim_cur_frame + 1) % anim.frameCount
	r.UpdateModelAnimation(actor.model, anim, actor.anim_cur_frame)
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
