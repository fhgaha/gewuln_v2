package gewuln

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
	speed_up:       f32,
}

Main_Actor_State :: struct {
	intersected_interactables: [dynamic]Interactable,
	interact_anim_ended:       bool,
	cur_interactable:          struct {
		interactable_name:     string,
		interact_target_found: bool,
	},
	dialogue_state:            struct {
		dialogue_target_found: bool,
		dialogue_ended:        bool,
	},
	stair_state:               struct {
		stair_target_found: bool,
		cur_path_point_idx: int,
	},
}

FXAA_Settings :: struct {
	intensity:     f32, // = 0.3
	shader:        r.Shader,
	intensity_loc: i32,
}

render_target: r.RenderTexture2D
font: r.Font
game_config_data := #load("../config.toml")
game_config: ^toml.Table
fxaa: FXAA_Settings
flags: bit_set[Flags]
input: Input_State
game_state: Game_State
main_actor: ^Actor
accumulated_time: f32

debug_lines: [dynamic]DebugLine


levels_datas: [dynamic]Level_Data
all_actors: map[string]Actor
level: Level
main_actor_state: Main_Actor_State


main :: proc() {
	r.SetConfigFlags({.VSYNC_HINT, .MSAA_4X_HINT, .WINDOW_RESIZABLE})

	r.InitWindow(WINDOW_WIDTH, WINDOW_HEIGHT, "gewuln")
	r.SetTargetFPS(60)
	r.DisableCursor()

	fxaa.shader = r.LoadShader(nil, "assets/shaders/fxaa.fs")
	defer r.UnloadShader(fxaa.shader)

	fxaa_resolution_loc := r.GetShaderLocation(fxaa.shader, "resolution")
	resolution := [2]f32{f32(RENDER_WIDTH), f32(RENDER_HEIGHT)}
	r.SetShaderValue(fxaa.shader, fxaa_resolution_loc, &resolution, .VEC2)

	fxaa.intensity_loc = r.GetShaderLocation(fxaa.shader, "intensity")
	r.SetShaderValue(fxaa.shader, fxaa.intensity_loc, &fxaa.intensity, .FLOAT)

	font = r.LoadFont("assets/fonts/centurygothic/centurygothic_bold.ttf")
	r.SetTextureFilter(font.texture, .BILINEAR)
	defer r.UnloadFont(font)

	render_target = r.LoadRenderTexture(RENDER_WIDTH, RENDER_HEIGHT)
	// r.SetTextureFilter(render_target.texture, .BILINEAR)
	defer r.UnloadRenderTexture(render_target)


	setup()

	//testing
	// actor_update_pos_and_yaw(main_actor, vec3{-3, 0, -3}, 180)

	for !r.WindowShouldClose() {
		read_input()
		update()

		dt := r.Clamp(r.GetFrameTime(), 0, MAX_DT)
		accumulated_time += dt * game_state.speed_up

		for accumulated_time >= DT {
			fixed_update(DT)
			accumulated_time -= DT
		}
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

	// levels, game_state.cur_level_name = create_levels(game_config)

	all_actors = create_actors_from_toml(game_config)
	levels_datas = create_levels_datas(game_config)
	first_level_name, ok := toml.get_string(game_config, "first_level_name"); assert(ok)
	game_state.cur_level_name = first_level_name
	load_level(&game_state, first_level_name)

	main_actor = &cur_level().actors["mona"]

	// searching neck bone index
	for i in 0 ..< main_actor.model.boneCount {
		bone_name := string(cast(cstring)&main_actor.model.bones[i].name[0])
		if strings.contains(strings.to_lower(bone_name), "neck") {
			fmt.printf("Found neck bone at index: %d\n", i)
			main_actor.neck_bone_index = i
		}
	}
}

read_input :: proc() {
	input = get_player_input()

	// debug input
	if r.IsKeyReleased(.ONE) do flags ~= {.small_res}
	if r.IsKeyReleased(.TWO) do flags ~= {.show_gizmos}
	if r.IsKeyReleased(.THREE) {
		flags ~= {.lock_cursor}
		if .lock_cursor in flags {r.DisableCursor()} else {r.EnableCursor()}
	}
	if r.IsKeyDown(.J) {
		fxaa.intensity = r.Clamp(fxaa.intensity + 0.1, 0.0, 1.0)
		r.SetShaderValue(fxaa.shader, fxaa.intensity_loc, &fxaa.intensity, .FLOAT)
		fmt.println("fxaa.intensity: ", fxaa.intensity)
	}
	if r.IsKeyDown(.K) {
		fxaa.intensity = r.Clamp(fxaa.intensity - 0.1, 0.0, 1.0)
		r.SetShaderValue(fxaa.shader, fxaa.intensity_loc, &fxaa.intensity, .FLOAT)
		fmt.println("fxaa.intensity: ", fxaa.intensity)
	}

	//fixed timestep (the "accumulator" pattern)
	if r.IsKeyDown(.LEFT_SHIFT) {
		game_state.speed_up = 2
	} else {
		game_state.speed_up = 1
	}
}

update :: proc() {
	if .paused in flags do return

	// update interact targets
	{
		intersected_interactables: []Interactable
		intersecting_intr: bool
		intersected_interactables, intersecting_intr = get_interactable_colliding_actor(
			cur_level().interactables[:],
			main_actor,
		)

		looking_at_intr: bool
		if intersecting_intr {
			_, looking_at_intr = actor_is_looking_at_point(
				main_actor,
				get_interactable_center(&intersected_interactables[0]),
			)
		}

		main_actor_state.cur_interactable.interact_target_found =
			intersecting_intr && looking_at_intr
	}

	update_actor_events(main_actor)
	actor_transition_state(main_actor)
}

fixed_update :: proc(DT: f32) {
	update_cam(DT)

	for _, &actor in cur_level().actors {
		actor_anim_update(&actor)
	}

	update_actor_step(main_actor, DT)
}


draw :: proc() {
	r.BeginDrawing()
	{
		r.ClearBackground(DARK)

		if .small_res in flags {
			r.BeginTextureMode(render_target)
			{
				render_3d_scene()
				draw_dialogue() //
			}
			r.EndTextureMode()

			r.BeginShaderMode(fxaa.shader)
			{
				r.DrawTexturePro(
					texture = render_target.texture,
					source = r.Rectangle{0, 0, RENDER_WIDTH, -RENDER_HEIGHT},
					dest = r.Rectangle{0, 0, WINDOW_WIDTH, WINDOW_HEIGHT},
					origin = vec2{0, 0},
					rotation = 0,
					tint = r.WHITE,
				)
				// draw_dialogue()		
			}
			r.EndShaderMode()
		} else {
			render_3d_scene()
			draw_dialogue() //
		}

		// draw_dialogue()
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
		for _, &actor in cur_level().actors {
			r.DrawModel(actor.model, actor.pos, 1, r.WHITE)
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

	for _, &a in cur_level().actors {
		for &c in a.dialogue_cameras {
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
}

draw_dialogue :: proc() {
	if main_actor.state != .DIALOGUE do return
	if len(cur_dialogue.lines) == 0 do return
	w := WINDOW_WIDTH; h := WINDOW_HEIGHT
	fs_name := FONT_SIZE_ACTOR_NAME; fs_line := FONT_SIZE_ACTOR_LINE
	if .small_res in flags {
		w = RENDER_WIDTH; h = RENDER_HEIGHT
		fs_name = FONT_SIZE_ACTOR_NAME * 0.5
		fs_line = FONT_SIZE_ACTOR_LINE * 0.5
	}
	draw_text_with_border(
		font = font,
		text = get_dialogue_speaker_name(),
		size = fs_name,
		pos_y = f32(h) * 0.7,
		spacing = FONT_SPACING,
		text_color = r.BLACK,
		border_color = r.WHITE,
		border_thickness = BORDER_THICKNESS,
		screen_width = f32(w),
	)
	draw_text_with_border(
		font = font,
		text = get_dialogue_text(),
		size = fs_line,
		pos_y = f32(h) * 0.8,
		spacing = FONT_SPACING,
		text_color = r.RAYWHITE,
		border_color = r.BLACK,
		border_thickness = BORDER_THICKNESS,
		screen_width = f32(w),
	)
}

draw_text_with_border :: proc(
	font: r.Font,
	text: string,
	size: f32,
	pos_y: f32,
	spacing: f32,
	text_color: r.Color,
	border_color: r.Color,
	border_thickness: f32,
	screen_width: f32,
) {
	text_c := strings.clone_to_cstring(text)
	text_size := r.MeasureTextEx(font, text_c, size, FONT_SPACING)
	pos := vec2{screen_width * 0.5 - text_size.x * 0.5, pos_y}

	// Loop through an 8-directional grid around the central position
	for dx: f32 = -1; dx <= 1; dx += 1 {
		for dy: f32 = -1; dy <= 1; dy += 1 {
			if dx == 0 && dy == 0 do continue // Skip center for now

			// Calculate the outer perimeter boundary
			offset := vec2{dx * border_thickness, dy * border_thickness}
			r.DrawTextEx(font, text_c, pos + offset, size, spacing, border_color)
		}
	}

	// Finally, layer the pristine text directly over the core center
	r.DrawTextEx(font, text_c, pos, size, spacing, text_color)
}
