package gewuln

import r "vendor:raylib"

vec2 :: [2]f32
vec3 :: [3]f32
vec4 :: [4]f32

tri2 :: [3]vec2
tri3 :: [3]vec3

WINDOW_WIDTH :: 1280
WINDOW_HEIGHT :: 720

// RENDER_WIDTH :: 320
// RENDER_HEIGHT :: 180

RENDER_WIDTH :: 640
RENDER_HEIGHT :: 360

MAX_DT :: 0.25
DT :: 1.0 / 60.0 // 16 ms, 0.016 s

DARK :: r.Color{40, 40, 40, 255}
FOV_DEG :: 90

LEFT :: vec3{1, 0, 0}
RIGHT :: vec3{-1, 0, 0}
UP :: vec3{0, 1, 0}
DOWN :: vec3{0, -1, 0}
FORWARD :: vec3{0, 0, 1}
BACKWARD :: vec3{0, 0, -1}

// neck rotation
ACTOR_NECK_MAX_YAW_DEG :: 70
ACTOR_NECK_MAX_PITCH_DEG :: 30

FONT_SIZE_ACTOR_NAME: f32 = 36
FONT_SIZE_ACTOR_LINE: f32 = 36
FONT_SPACING: f32 = 0
BORDER_THICKNESS: f32 = 2
