package core

import "core:fmt"
import "core:math/linalg"
import r "vendor:raylib"

Flags :: enum {
	smal_res,
	show_gizmos,
	disable_cursor,
}
flags: bit_set[Flags]

input: Input_State

font: r.Font
cam: r.Camera3D
cam_mode: r.CameraMode

room: r.Model
actor: Actor
walk_area_model: r.Model
walk_area_tris: [dynamic]tri3
interactables: [dynamic]Interactable


main :: proc() {
	flags = {.show_gizmos}

	r.SetConfigFlags({.VSYNC_HINT, .MSAA_4X_HINT})

	r.InitWindow(WINDOW_WIDTH, WINDOW_HEIGHT, "gewuln")
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

	//load the room scene and walk area separately
	room = r.LoadModel("assets/models/test_rooms/export/test_floor/glb/test_rooms.glb")
	defer r.UnloadModel(room)


	//get metadata
	transl := load_glb_custom_properties(
		"assets/models/test_rooms/export/test_floor/glb/test_rooms.glb",
	)
	actor_pos_update(transl)
	
	
	walk_area_model = r.LoadModel("assets/models/test_rooms/export/test_floor/glb/walk_area.glb")
	defer r.UnloadModel(walk_area_model)
	extract_tris(&walk_area_model, &walk_area_tris)

	//interactables
	//TODO defer delete, unload
	append(&interactables, Interactable {
		name = "interactable_h_half",
		model = r.LoadModel(
			"assets/models/test_rooms/export/test_floor/glb/interactable_h_half.glb",
		),
		action = proc(intr: Interactable) {
			fmt.println("action of interactable_h_half")
		},
	})
	append(&interactables, Interactable {
		name = "interactable_h_2",
		model = r.LoadModel("assets/models/test_rooms/export/test_floor/glb/interactable_h_2.glb"),
		action = proc(intr: Interactable) {
			fmt.println("action of interactable_h_2")
		},
	})
	defer for intr in interactables {
		r.UnloadModel(intr.model)
	}


	render_target := r.LoadRenderTexture(RENDER_WIDTH, RENDER_HEIGHT)
	defer r.UnloadRenderTexture(render_target)


	for !r.WindowShouldClose() {
		dt := r.GetFrameTime()
		input = get_player_input()

		//input
		if r.IsKeyPressed(.ONE) do flags ~= {.smal_res}
		if r.IsKeyPressed(.TWO) do flags ~= {.show_gizmos}
		if r.IsKeyPressed(.THREE) do flags ~= {.disable_cursor}

		if .disable_cursor in flags {r.DisableCursor()} else {r.EnableCursor()}

		switch actor.state {
		case .IDLE:
			handle_idle(dt)
		case .WALK:
			handle_walk(dt)
		case .INTERACT:
			handle_interact()
		}


		//update
		update_actor_anim(&actor)
		update_cam(dt)


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

	r.BeginMode3D(cam)
	{
		r.DrawModel(room, vec3{0, 0, 0}, 1, r.GRAY)
		if .show_gizmos in flags {
			r.DrawModelWires(walk_area_model, vec3{0, 0, 0}, 1, r.ORANGE)

			draw_interactables()
		}

		r.DrawModel(actor.model, actor.pos, 1, r.WHITE)
		// r.DrawModelWires(actor.model, vec3{0, 0, 0}, 1, r.WHITE)

		if .show_gizmos in flags {
			r.DrawBoundingBox(actor.bounding_box, r.MAGENTA)

			for &tr in walk_area_tris {
				r.DrawCylinderEx(tr[0], tr[1], 0.02, 0.02, 2, r.SKYBLUE)
				r.DrawCylinderEx(tr[1], tr[2], 0.02, 0.02, 2, r.SKYBLUE)
				r.DrawCylinderEx(tr[2], tr[0], 0.02, 0.02, 2, r.SKYBLUE)
			}
		}

		r.DrawTriangle3D({1, 1, 1}, {0, 0, 0}, {-1, -1, -1}, r.RED)


		if .show_gizmos in flags {
			draw_gizmo()
		}
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
