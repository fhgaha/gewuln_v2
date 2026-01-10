package core

import r "vendor:raylib"

vec2 :: [2]f32
vec3 :: [3]f32
vec4 :: [4]f32

tri :: [3]vec3

WINDOW_WIDTH :: 1280
WINDOW_HEIGHT :: 720

RENDER_WIDTH :: 320
RENDER_HEIGHT :: 180

DARK :: r.Color{40, 40, 40, 255}
FOV_DEG :: 90

LEFT :: vec3{1, 0, 0}
RIGHT :: vec3{-1, 0, 0}
UP :: vec3{0, 1, 0}
DOWN :: vec3{0, -1, 0}
FORWARD :: vec3{0, 0, 1}
BACKWARD :: vec3{0, 0, -1}
