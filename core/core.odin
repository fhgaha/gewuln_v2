package core

import "core:fmt"
import "core:math"
import "core:strings"
import "core:unicode/utf8"
import r "vendor:raylib"

font: r.Font
cam: r.Camera3D
cam_mode: r.CameraMode

room: r.Model
actor: Actor
walk_area_model: r.Model

small_resolution := true

actor_state: Actor_State

main :: proc() {
	//this raylib setup should be in top for some reason
	r.InitWindow(WINDOW_WIDTH, WINDOW_HEIGHT, "ogewuln")
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
	cam_mode = r.CameraMode.CUSTOM

	//actor
	// model_path: cstring = "assets/models/robot/robot.glb"
	actor_path: cstring = "assets/models/mona_sax/export/glb/mona.glb"
	actor_model := r.LoadModel(actor_path)
	defer r.UnloadModel(actor_model)
	actor_coll_path: cstring = "assets/models/mona_sax/export/glb/collider.glb"
	actor_coll_model := r.LoadModel(actor_coll_path)
	defer r.UnloadModel(actor_coll_model)

	actor = Actor {
		speed        = 2,
		rot_speed    = 4,
		model        = actor_model,
		bounding_box = r.GetModelBoundingBox(actor_coll_model),
		anims_names  = make(map[string]i32),
	}
	actor.anims = r.LoadModelAnimations(actor_path, &actor.anims_count)
	assert(actor.anims_count > 0, "Actor should have at least one animation")
	defer r.UnloadModelAnimations(actor.anims, actor.anims_count)
	defer r.UnloadModel(actor.model)

	for &a, i in actor.anims[:actor.anims_count] {
		name_cstr := cstring(&a.name[0])
		name_str := string(name_cstr)
		actor.anims_names[name_str] = i32(i)
		fmt.println("+++ ", name_str, ": ", actor.anims_names[name_str])
	}


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
		case r.IsKeyPressed(.ONE):
			actor.anim_idx = (actor.anim_idx + 1) % actor.anims_count
		case r.IsKeyPressed(.TWO):
			actor.anim_idx = (actor.anim_idx + actor.anims_count - 1) % actor.anims_count
		case r.IsKeyPressed(.R):
			small_resolution = !small_resolution
		}


		move_key_pressed := false

		turn :: proc() {
			if r.IsKeyDown(.A) {
				actor.model.transform *= r.MatrixRotateY(actor.rot_speed * r.DEG2RAD)
			}
			if r.IsKeyDown(.D) {
				actor.model.transform *= r.MatrixRotateY(-actor.rot_speed * r.DEG2RAD)
			}
		}

		handle_idle :: proc() {
			// fmt.println("handle_idle")
			actor.anim_idx = actor.anims_names["idle"]
			turn()
			walk_cond := r.IsKeyDown(.W) || r.IsKeyDown(.S)
			if walk_cond {
				actor_state = .WALK
			}
		}
		handle_walk :: proc(dt: f32) {
			// fmt.println("handle_walk")
			actor.anim_idx = actor.anims_names["walk"]
			turn()

			velocity: vec3
			if r.IsKeyDown(.W) {
				actor.dir = r.Vector3Normalize(actor.dir + FORWARD)
			}
			if r.IsKeyDown(.S) {
				actor.dir = r.Vector3Normalize(actor.dir + BACKWARD)
			}
			velocity += actor.dir * actor.speed * dt
			actor.model.transform *= r.MatrixTranslate(velocity.x, velocity.y, velocity.z)
			idle_cond := !(r.IsKeyDown(.W) || r.IsKeyDown(.S)) || r.Vector3Length(velocity) == 0
			if idle_cond {
				actor_state = .IDLE
			}
		}

		switch actor_state {
		case .IDLE:
			handle_idle()
		case .WALK:
			handle_walk(dt)
		case .INTERACT:

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

// move_model: proc(model: Og_Model){

// }


update_model_anim :: proc(actor: ^Actor) {
	anim := actor.anims[actor.anim_idx]
	actor.anim_cur_frame = (actor.anim_cur_frame + 1) % anim.frameCount
	r.UpdateModelAnimation(actor.model, anim, actor.anim_cur_frame)
}


render_3d_scene :: proc() {
	r.ClearBackground(DARK)

	r.BeginMode3D(cam)
	{
		r.DrawModel(room, vec3{0, 0, 0}, 1, r.GRAY)
		r.DrawModelWires(walk_area_model, vec3{0, 0, 0}, 1, r.ORANGE)
		r.DrawModel(actor.model, actor.pos, 1, r.WHITE)
		r.DrawModelWires(actor.model, actor.pos, 1, r.WHITE)
		r.DrawBoundingBox(actor.bounding_box, r.MAGENTA)

		// r.DrawGrid(slices = 10, spacing = 1)
		draw_gizmo()
	}
	r.EndMode3D()
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
