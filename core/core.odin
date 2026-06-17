package core

import "../packages/toml"
import "core:fmt"
import "core:strings"
import r "vendor:raylib"

Flags :: enum {
	small_res,
	show_gizmos,
	lock_cursor,
	paused,
	camera_debug,
	camera_follow,
	print_debug_info,
}

Game_State :: struct {
	cur_level_name: string,
	levels:         map[string]Level,
}

game_config_data := #load("../config.toml")
game_config: ^toml.Table

flags: bit_set[Flags]
input: Input_State
font: r.Font
game_state: Game_State
main_actor: ^Actor
accumulated_time: f32
fxaa_intensity: f32 = 0.3
render_target: r.RenderTexture2D
fxaa_shader: r.Shader
fxaa_intensity_loc: i32

debug_lines: [dynamic]DebugLine

main :: proc() {
	r.SetConfigFlags({.VSYNC_HINT, .MSAA_4X_HINT, .WINDOW_RESIZABLE})

	r.InitWindow(WINDOW_WIDTH, WINDOW_HEIGHT, "gewuln")
	r.SetTargetFPS(60)
	r.DisableCursor()

	fxaa_shader = r.LoadShader(nil, "assets/shaders/fxaa.fs")
	defer r.UnloadShader(fxaa_shader)

	fxaa_resolution_loc := r.GetShaderLocation(fxaa_shader, "resolution")
	resolution := [2]f32{f32(RENDER_WIDTH), f32(RENDER_HEIGHT)}
	r.SetShaderValue(fxaa_shader, fxaa_resolution_loc, &resolution, .VEC2)

	fxaa_intensity_loc = r.GetShaderLocation(fxaa_shader, "intensity")
	r.SetShaderValue(fxaa_shader, fxaa_intensity_loc, &fxaa_intensity, .FLOAT)

	font = r.LoadFont("assets/fonts/centurygothic/centurygothic_bold.ttf")
	r.SetTextureFilter(font.texture, .BILINEAR)
	defer r.UnloadFont(font)

	render_target = r.LoadRenderTexture(RENDER_WIDTH, RENDER_HEIGHT)
	// r.SetTextureFilter(render_target.texture, .BILINEAR)
	defer r.UnloadRenderTexture(render_target)


	setup()

	for !r.WindowShouldClose() {
		update()
		draw()

		free_all(context.temp_allocator)
	}

	r.CloseWindow()
}

setup :: proc() {
	flags = {.lock_cursor, .camera_debug, .show_gizmos, .print_debug_info}

	err: toml.Error
	game_config, err = toml.parse_data(game_config_data)
	assert(err.type == .None, fmt.enum_value_to_string(err.type) or_else "an error")

	game_state.levels, game_state.cur_level_name = create_levels(game_config)
	main_actor = &game_state.levels["test_room"].actors["mona"]


	// searching neck bone index
	for i in 0 ..< main_actor.model.boneCount {
		bone_name := string(cast(cstring)&main_actor.model.bones[i].name[0])
		if strings.contains(strings.to_lower(bone_name), "neck") {
			fmt.printf("Found neck bone at index: %d\n", i)
			main_actor.neck_bone_index = i
		}
	}
}

update :: proc() {
	//fixed timestep (the "accumulator" pattern)
	dt := r.Clamp(r.GetFrameTime(), 0, max_dt)
	accumulated_time += dt

	for accumulated_time >= DT {

		if .paused in flags do break

		input = get_player_input()

		//input
		if r.IsKeyReleased(.ONE) do flags ~= {.small_res}
		if r.IsKeyReleased(.TWO) do flags ~= {.show_gizmos}
		if r.IsKeyReleased(.THREE) {
			flags ~= {.lock_cursor}
			if .lock_cursor in flags {r.DisableCursor()} else {r.EnableCursor()}
		}
		if r.IsKeyDown(.J) {
			fxaa_intensity = r.Clamp(fxaa_intensity + 0.1, 0.0, 1.0)
			r.SetShaderValue(fxaa_shader, fxaa_intensity_loc, &fxaa_intensity, .FLOAT)
			fmt.println("fxaa_intensity: ", fxaa_intensity)
		}
		if r.IsKeyDown(.K) {
			fxaa_intensity = r.Clamp(fxaa_intensity - 0.1, 0.0, 1.0)
			r.SetShaderValue(fxaa_shader, fxaa_intensity_loc, &fxaa_intensity, .FLOAT)
			fmt.println("fxaa_intensity: ", fxaa_intensity)
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
		for k, &v in cur_level().actors {
			actor_anim_update(&v)
		}
		update_cam(DT)

		accumulated_time -= DT

	}
}

draw :: proc() {
	r.BeginDrawing()
	{
		r.ClearBackground(DARK)

		if .small_res in flags {
			r.BeginTextureMode(render_target)
			{
				render_3d_scene()
			}
			r.EndTextureMode()

			r.BeginShaderMode(fxaa_shader)
			{
				r.DrawTexturePro(
					texture = render_target.texture,
					source = r.Rectangle{0, 0, RENDER_WIDTH, -RENDER_HEIGHT},
					dest = r.Rectangle{0, 0, WINDOW_WIDTH, WINDOW_HEIGHT},
					origin = vec2{0, 0},
					rotation = 0,
					tint = r.WHITE,
				)
			}
			r.EndShaderMode()
		} else {
			render_3d_scene()
		}

		draw_fps()
	}
	r.EndDrawing()
}

render_3d_scene :: proc() {
	r.ClearBackground(DARK)

	r.BeginMode3D(cur_level().cam^)
	{
		// draw level objects
		for i in 0 ..< cur_level().room.meshCount {
			if is_interactable_mesh(cur_level().interactables[:], i) do continue
			dont_draw_walk_area :=
				cur_level().walk_area_mesh_idx != -1 && i32(i) == cur_level().walk_area_mesh_idx
			if dont_draw_walk_area do continue
			r.DrawMesh(
				cur_level().room.meshes[i],
				cur_level().room.materials[cur_level().room.meshMaterial[i]],
				r.Matrix(1),
			)
		}

		// draw actors
		for k, &v in cur_level().actors {
			r.DrawModel(v.model, v.pos, 1, r.WHITE)
		}

		if .show_gizmos in flags {
			draw_interactables()

			r.DrawBoundingBox(main_actor.bounding_box, r.MAGENTA)

			draw_walking_area()
			draw_gizmo()
			draw_cameras()
			draw_debug_lines()
		}
	}
	r.EndMode3D()
}

draw_interactables :: proc(color: r.Color = r.RED) {
	for intr in cur_level().interactables {
		bb := r.GetMeshBoundingBox(cur_level().room.meshes[intr.mesh_index])
		r.DrawBoundingBox(bb, color)
		center := (bb.max + bb.min) * 0.5
		r.DrawSphereWires(center, 0.1, 3, 4, color)
	}
}

draw_gizmo :: proc() {
	dist := r.Vector3Distance(cur_level().cam.position, vec3{0, 0, 0})
	r.DrawCylinderEx(vec3{0, 0, 0}, vec3{1, 0, 0} * dist, 0.02, 0.02, 2, r.RED)
	r.DrawCylinderEx(vec3{0, 0, 0}, vec3{0, 1, 0} * dist, 0.02, 0.02, 2, r.GREEN)
	r.DrawCylinderEx(vec3{0, 0, 0}, vec3{0, 0, 1} * dist, 0.02, 0.02, 2, r.BLUE)
}

draw_walking_area :: proc() {
	color := r.SKYBLUE
	for &tr in cur_level().walk_area_tris {
		r.DrawCylinderEx(tr[0], tr[1], 0.02, 0.02, 2, color)
		r.DrawCylinderEx(tr[1], tr[2], 0.02, 0.02, 2, color)
		r.DrawCylinderEx(tr[2], tr[0], 0.02, 0.02, 2, color)
	}
}

draw_debug_lines :: proc() {
	for l in debug_lines {
		r.DrawLine3D(l.start, l.end, l.color)
	}
	clear(&debug_lines)
}

draw_fps :: proc() {
	r.DrawTextEx(
		font,
		text = r.TextFormat("FPS: %d", r.GetFPS()),
		position = 0,
		fontSize = 24,
		spacing = 0,
		tint = r.ORANGE,
	)
}

draw_cameras :: proc() {
	for _, &c in cur_level().cameras {
		if &c != cur_level().cam {
			r.DrawCylinderWiresEx(
				c.position,
				c.position + r.Vector3Normalize(c.target - c.position),
				0.02,
				1,
				8,
				r.YELLOW,
			)
		}
	}

}
