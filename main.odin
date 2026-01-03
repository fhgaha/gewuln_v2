package main

import r "vendor:raylib"

SCREEN_WIDTH :: 1280
SCREEN_HEIGHT :: 720

vec2 :: [2]f32
vec3 :: [3]f32
vec4 :: [4]f32
DARK :: r.Color{20, 20, 20, 255}
FOV_DEG :: 90
FOV_HALF_DEG :: FOV_DEG / 2

main :: proc() {
	r.SetConfigFlags({.VSYNC_HINT})
	r.InitWindow(SCREEN_WIDTH, SCREEN_HEIGHT, "My Odin + Raylib game")

	r.SetTargetFPS(60)
	font := r.LoadFont("assets/centurygothic/centurygothic_bold.ttf")

	cam := r.Camera3D {
		position   = vec3{0, 10, 10},
		target     = vec3{0, 0, 0},
		up         = vec3{0, 1, 0},
		fovy       = FOV_HALF_DEG,
		projection = .PERSPECTIVE,
	}

	cube_pos := vec3{0, 0, 0}

	for !r.WindowShouldClose() {
		r.BeginDrawing()

		r.ClearBackground(DARK)

		r.BeginMode3D(cam)

		r.DrawCube(position = cube_pos, width = 2, height = 2, length = 2, color = r.RED)
		r.DrawGrid(slices = 10, spacing = 1)

		r.EndMode3D()

		r.DrawTextEx(font, r.TextFormat("FPS: %d", r.GetFPS()), 0, 36, 0, r.ORANGE)

		r.EndDrawing()
	}

	r.UnloadFont(font)
	r.CloseWindow()
}
