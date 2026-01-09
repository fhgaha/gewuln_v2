package core

import "core:fmt"
import "core:math/linalg"
import r "vendor:raylib"

font: r.Font
cam: r.Camera3D
cam_mode: r.CameraMode

room: r.Model
actor: Actor
walk_area_model: r.Model

small_resolution := false

main :: proc() {
	//this raylib setup should be in top for some reason
	r.InitWindow(WINDOW_WIDTH, WINDOW_HEIGHT, "gewuln")
	r.SetTraceLogLevel(.ALL)
	r.SetConfigFlags({.VSYNC_HINT})
	r.SetTargetFPS(60)
	r.DisableCursor()

	font = r.LoadFont("assets/fonts/centurygothic/centurygothic_bold.ttf")
	r.SetTextureFilter(font.texture, .BILINEAR)
	defer r.UnloadFont(font)

	//set up
	cam = r.Camera3D {
		position   = vec3{1, 2, 4},
		target     = vec3{0, 1, 0},
		up         = vec3{0, 1, 0},
		fovy       = FOV_DEG / 2,
		projection = .PERSPECTIVE,
	}
	cam_mode = r.CameraMode.CUSTOM

	ok := create_actor(
		&actor,
		"assets/models/mona_sax/export/glb/mona.glb",
		"assets/models/mona_sax/export/glb/collider.glb",
	)
	assert(ok)

	//room
	room_path: cstring = "assets/models/test_rooms/export/test_floor/glb/test_rooms.glb"
	room = r.LoadModel(room_path)
	defer r.UnloadModel(room)

	walk_area_path: cstring = "assets/models/test_rooms/export/test_floor/glb/walk_area.glb"
	walk_area_model = r.LoadModel(walk_area_path)
	walk_area_bb: r.BoundingBox = r.GetModelBoundingBox(walk_area_model)
	defer r.UnloadModel(walk_area_model)

	target := r.LoadRenderTexture(RENDER_WIDTH, RENDER_HEIGHT)
	defer r.UnloadRenderTexture(target)


	for !r.WindowShouldClose() {
		dt := r.GetFrameTime()

		//input
		switch {
		case r.IsKeyPressed(.R):
			small_resolution = !small_resolution
		}

		turn :: proc() {
			if r.IsKeyDown(.A) {
				actor.model.transform *= r.MatrixRotateY(actor.rot_speed * r.DEG2RAD)
			}
			if r.IsKeyDown(.D) {
				actor.model.transform *= r.MatrixRotateY(-actor.rot_speed * r.DEG2RAD)
			}
		}

		input_dir :: proc() -> i32 {
			input_dir: i32
			if r.IsKeyDown(.W) {
				input_dir += 1
			}
			if r.IsKeyDown(.S) {
				input_dir -= 1
			}
			return input_dir
		}

		handle_idle :: proc() {
			play_anim(&actor.animator, .IDLE)
			turn()
			input_dir := input_dir()
			walk_cond := input_dir != 0
			interact_cond := r.IsKeyPressed(.E)
			switch {
			case walk_cond:
				actor.state = .WALK
				fmt.println("handle_walk")
			case interact_cond:
				actor.state = .INTERACT
				fmt.println("handle_interact")
			}
		}


		handle_walk :: proc(dt: f32) {
			play_anim(&actor.animator, .WALK)
			turn()
			input_dir := f32(input_dir()) //-1, 0 or 1
			vel: vec3 = input_dir * actor.speed * dt * FORWARD
			actor.model.transform *= r.MatrixTranslate(vel.x, vel.y, vel.z)
			
			//translate actor bounding box
			vel2: vec3 = input_dir * actor.speed * dt * actor_dir(&actor)
			bb := actor.bounding_box
			min := r.MatrixTranslate(vel2.x, vel2.y, vel2.z) * vec4{bb.min.x, bb.min.y, bb.min.z, 1}
			max := r.MatrixTranslate(vel2.x, vel2.y, vel2.z) * vec4{bb.max.x, bb.max.y, bb.max.z, 1}
			actor.bounding_box.min = vec3{min.x, min.y, min.z}
			actor.bounding_box.max = vec3{max.x, max.y, max.z}

			// fmt.println("vel len: ", r.Vector3Length(velocity))
			should_move := r.IsKeyDown(.W) || r.IsKeyDown(.S)
			is_moving := r.Vector3Length(vel) != 0
			idle_cond := !should_move && !is_moving
			if idle_cond {
				actor.state = .IDLE
				fmt.println("handle_idle")
			}
			interact_cond := r.IsKeyPressed(.E)
			if interact_cond {
				actor.state = .INTERACT
				fmt.println("handle_interact")
			}
		}

		handle_interact :: proc() {
			play_anim(&actor.animator, .INTERACT)
			idle_cond := last_frame_reached(&actor.animator)
			if idle_cond {
				actor.state = .IDLE
				fmt.println("handle_idle")
			}
		}

		switch actor.state {
		case .IDLE:
			handle_idle()
		case .WALK:
			handle_walk(dt)
		case .INTERACT:
			handle_interact()
		}


		//update
		update_model_anim(&actor)
		r.UpdateCamera(&cam, cam_mode)


		r.BeginDrawing()
		{
			r.ClearBackground(DARK)

			switch small_resolution {
			case true:
				r.BeginTextureMode(target)
				{
					render_3d_scene()
				}
				r.EndTextureMode()

				r.DrawTexturePro(
					texture = target.texture,
					source = r.Rectangle{0, 0, RENDER_WIDTH, -RENDER_HEIGHT},
					dest = r.Rectangle{0, 0, WINDOW_WIDTH, WINDOW_HEIGHT},
					origin = vec2{0, 0},
					rotation = 0,
					tint = r.WHITE,
				)
			case false:
				render_3d_scene()
			}

			draw_fps()
		}
		r.EndDrawing()

		free_all(context.temp_allocator)
	}


	r.CloseWindow()
}

render_3d_scene :: proc() {
	r.ClearBackground(DARK)

	r.BeginMode3D(cam)
	{
		r.DrawModel(room, vec3{0, 0, 0}, 1, r.GRAY)
		r.DrawModelWires(walk_area_model, vec3{0, 0, 0}, 1, r.ORANGE)
		r.DrawModel(actor.model, vec3{0, 0, 0}, 1, r.WHITE)
		r.DrawModelWires(actor.model, vec3{0, 0, 0}, 1, r.WHITE)
		r.DrawBoundingBox(actor.bounding_box, r.MAGENTA)

		r.DrawGrid(slices = 10, spacing = 1)
		draw_gizmo()
	}
	r.EndMode3D()
}


draw_gizmo :: proc() {
	dist := r.Vector3Distance(cam.position, vec3{0, 0, 0})
	r.DrawCylinderEx(vec3{0, 0, 0}, vec3{1, 0, 0} * dist, 0.02, 0.02, 2, r.RED)
	r.DrawCylinderEx(vec3{0, 0, 0}, vec3{0, 1, 0} * dist, 0.02, 0.02, 2, r.GREEN)
	r.DrawCylinderEx(vec3{0, 0, 0}, vec3{0, 0, 1} * dist, 0.02, 0.02, 2, r.BLUE)
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
