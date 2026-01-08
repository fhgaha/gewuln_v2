package core

import r "vendor:raylib"

Actor :: struct {
	pos:                                   vec3,
	dir:                                   vec3,
	speed, rot_speed:                      f32,
	model:                                 r.Model,
	bounding_box:                          r.BoundingBox,
	//animations
	anims_count, anim_idx, anim_cur_frame: i32,
	anims:                                 [^]r.ModelAnimation, //ptr to array
	anims_names:                           map[string]i32,
}

vec2 :: [2]f32
vec3 :: [3]f32
vec4 :: [4]f32

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

Actor_State :: enum {
	IDLE,
	WALK,
	INTERACT,
}

