package core

import "../packages/toml"
import "core:fmt"
import r "vendor:raylib"

Flags :: enum {
	smal_res,
	show_gizmos,
	lock_cursor,
	paused,
}

Game_State :: struct {
	cur_level: string,
	levels:    map[string]Level,
}

Actors_Names :: enum {
	mona,
}

DT :: 1.0 / 60.0 // 16 ms, 0.016 s
game_config_data := #load("../config.toml")
game_config: ^toml.Table

flags: bit_set[Flags]
input: Input_State
font: r.Font
game_state: Game_State
main_actor: Actor
actors: [Actors_Names]Actor	// all actors including main actor
accumulated_time: f32


main :: proc() {
	flags = {.lock_cursor}

	r.SetConfigFlags({.VSYNC_HINT, .MSAA_4X_HINT, .WINDOW_RESIZABLE})

	r.InitWindow(WINDOW_WIDTH, WINDOW_HEIGHT, "gewuln")
	r.SetTargetFPS(60)
	r.DisableCursor()

	err1: toml.Error
	game_config, err1 = toml.parse_data(game_config_data)
	// game_config, err1 = toml.parse_file("config.toml")
	assert(err1.type == .None, fmt.enum_value_to_string(err1.type) or_else "an error")

	font = r.LoadFont("assets/fonts/centurygothic/centurygothic_bold.ttf")
	r.SetTextureFilter(font.texture, .BILINEAR)
	defer r.UnloadFont(font)

	main_actor = create_actor_from_toml(game_config)
	game_state.levels, game_state.cur_level = create_levels(game_config)

	actor_update_pos(&main_actor, cur_level().actor.pos)
	actor_update_yaw(&main_actor, cur_level().actor.yaw)

	render_target := r.LoadRenderTexture(RENDER_WIDTH, RENDER_HEIGHT)
	defer r.UnloadRenderTexture(render_target)


	for !r.WindowShouldClose() {

		//fixed timestep (the "accumulator" pattern)
		max_dt :: 0.25
		dt := r.Clamp(r.GetFrameTime(), 0, max_dt)
		accumulated_time += dt

		for accumulated_time >= DT {

			if .paused in flags do break

			input = get_player_input()

			//input
			if r.IsKeyReleased(.ONE) do flags ~= {.smal_res}
			if r.IsKeyReleased(.TWO) do flags ~= {.show_gizmos}
			if r.IsKeyReleased(.THREE) {
				flags ~= {.lock_cursor}
				if .lock_cursor in flags {r.DisableCursor()} else {r.EnableCursor()}
			}


			switch main_actor.state {
			case .IDLE:
				handle_idle(DT)
			case .WALK:
				handle_walk(DT)
			case .INTERACT:
				handle_interact()
			}

			//update
			actor_anim_update(&main_actor)
			update_cam(DT)

			accumulated_time -= DT

		}


		r.BeginDrawing()
		{
			r.ClearBackground(DARK)

			if .smal_res in flags {
				r.BeginTextureMode(render_target)
				{
					render_3d_scene()
				}
				r.EndTextureMode()

				r.DrawTexturePro(
					texture = render_target.texture,
					source = r.Rectangle{0, 0, RENDER_WIDTH, -RENDER_HEIGHT},
					dest = r.Rectangle{0, 0, WINDOW_WIDTH, WINDOW_HEIGHT},
					origin = vec2{0, 0},
					rotation = 0,
					tint = r.WHITE,
				)
			} else {
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

	r.BeginMode3D(cur_level().cam)
	{
		r.DrawModel(cur_level().room, vec3{0, 0, 0}, 1, r.GRAY)

		r.DrawModel(main_actor.model, main_actor.pos, 1, r.WHITE)
		// r.DrawModelWires(actor.model, actor.pos, 1, r.GREEN)

		r.DrawTriangle3D({1, 1, 1}, {0, 0, 0}, {-1, -1, -1}, r.RED)

		if .show_gizmos in flags {
			draw_interactables()

			r.DrawBoundingBox(main_actor.bounding_box, r.MAGENTA)

			draw_walking_area()
			draw_gizmo()
		}
	}
	r.EndMode3D()
}


draw_gizmo :: proc() {
	dist := r.Vector3Distance(cur_level().cam.position, vec3{0, 0, 0})
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

draw_walking_area :: proc() {
	for &tr in cur_level().walk_area_tris {
		r.DrawCylinderEx(tr[0], tr[1], 0.02, 0.02, 2, r.SKYBLUE)
		r.DrawCylinderEx(tr[1], tr[2], 0.02, 0.02, 2, r.SKYBLUE)
		r.DrawCylinderEx(tr[2], tr[0], 0.02, 0.02, 2, r.SKYBLUE)
	}
}
