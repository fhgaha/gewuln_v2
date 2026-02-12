package core

import "../packages/toml"
import "core:fmt"
import "core:math/linalg"
import r "vendor:raylib"


Level :: struct {
	name:            string,
	cam:             r.Camera3D,
	cam_mode:        r.CameraMode,
	room:            r.Model,
	walk_area_model: r.Model,
	walk_area_tris:  [dynamic]tri3,
	interactables:   [dynamic]Interactable,
}

create_level :: proc(section: ^toml.Table) -> Level {
	level1 := toml.get_table_panic(game_config, "levels", "level1")

	cam_pos_toml := toml.get_list_panic(level1, "camera", "pos")
	cam_pos: [3]f32
	for i in 0 ..< 3 {
		#partial switch v in cam_pos_toml[0] {
		case i64:
		case f64:
			cam_pos[i] = f32(v)
		}
	}


	cam_target_toml := toml.get_list_panic(level1, "camera", "target")
	cam_target: [3]f32
	for i in 0 ..< 3 {
		#partial switch v in cam_target_toml[0] {
		case i64:
		case f64:
			cam_target[i] = f32(v)
		}
	}

	return Level {
		name = "leve1",
		cam = r.Camera3D {
			position = cam_pos,
			target = cam_target,
			up = UP,
			fovy = FOV_DEG / 2,
			projection = .PERSPECTIVE,
		},
		cam_mode = r.CameraMode.CUSTOM,
	}


	/*	
	{ main_actor = { collider = "assets/models/mona_sax/export/glb/collider.glb", model = "assets/models/mona_sax/export/glb/mona.glb" }, levels = { level1 = { name = "level1", room_glb = "assets/models/test_rooms/export/test_floor/glb/test_rooms.glb", camera = { target = [ 0, 1, 0 ], pos = [ 1, 2, 4 ] }, walk_area_glb = "assets/models/test_rooms/export/test_floor/glb/walk_area.glb", interactables = [ { name 
= "interactable_h_half", glb = "assets/models/test_rooms/export/test_floor/glb/interactable_h_half.glb" }, { name = "interactable_h_2", glb = "assets/models/test_rooms/export/test_floor/glb/interactable_h_2.glb" } ] } } }
*/
}

load_level :: proc(lvl: Level) {

}

unload_level :: proc(lvl: Level) {

}

change_level :: proc(state: ^Game_State, next: Level) {
	unload_level(state.cur_level)
	load_level(next)
	state.cur_level = next
}
