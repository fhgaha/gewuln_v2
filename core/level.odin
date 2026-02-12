package core

import "../packages/toml"
import "core:fmt"
import "core:strings"
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

	// camera

	cam_pos_toml := toml.get_list_panic(level1, "camera", "pos")
	cam_pos: [3]f32
	for i in 0 ..< 3 {
		#partial switch v in cam_pos_toml[i] {
		case i64:
		case f64:
			cam_pos[i] = f32(v)
		}
	}

	cam_target_toml := toml.get_list_panic(level1, "camera", "target")
	cam_target: [3]f32
	for i in 0 ..< 3 {
		#partial switch v in cam_target_toml[i] {
		case i64:
		case f64:
			cam_target[i] = f32(v)
		}
	}

	// room

	room_glb := toml.get_string_panic(level1, "room_glb")
	room_glb_cstr := strings.clone_to_cstring(room_glb)
	room := r.LoadModel(room_glb_cstr)
	delete(room_glb_cstr)


	// custom props

	assert(main_actor.initialised)
	custom_props := load_glb_custom_properties(room_glb)
	actor_pos_update(custom_props.actor_pos)
	main_actor.yaw = custom_props.actor_yaw
	main_actor.model.transform = r.MatrixRotateY(main_actor.yaw)


	// walk area

	walk_area_glb := toml.get_string_panic(level1, "walk_area_glb")
	walk_area_glb_cstr := strings.clone_to_cstring(walk_area_glb)
	walk_area_model := r.LoadModel(walk_area_glb_cstr)
	delete(walk_area_glb_cstr)


	walk_area_tris: [dynamic]tri3
	extract_tris(&walk_area_model, &walk_area_tris)
	assert(len(walk_area_tris) > 0)

	// interactables

	interactables: [dynamic]Interactable

	interactables_toml := toml.get_list_panic(level1, "interactables")
	for intr in interactables_toml {
		intr_fields := intr.(^toml.Table)
		name_toml := toml.get_string_panic(intr_fields, "name")
		glb_toml := toml.get_string_panic(intr_fields, "glb")

		glb_toml_cstr := strings.clone_to_cstring(glb_toml)
		append(
			&interactables,
			Interactable {
				name = name_toml,
				model = r.LoadModel(glb_toml_cstr),
				action = proc(intr: Interactable) {
					// fmt.printfln("action of %s", name_)
				},
			},
		)
		delete(glb_toml_cstr)
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
		room = room,
		walk_area_model = walk_area_model,
		walk_area_tris = walk_area_tris,
		interactables = interactables,
	}
}

destroy_level :: proc() {}

load_level :: proc(lvl: ^Level) {

}

unload_level :: proc(lvl: ^Level) {
	cur_lvl := get_cur_level()

	r.UnloadModel(cur_lvl.walk_area_model)
	//TODO the rest
}

change_level :: proc(state: ^Game_State, next: ^Level) {
	unload_level(get_cur_level())
	load_level(next)
	state.cur_level = next.name
}

get_cur_level :: proc() -> ^Level {
	level_ptr, ok := &game_state.levels[game_state.cur_level]
	if !ok {
		fmt.print("Available levels: ")
		for k, _ in game_state.levels do fmt.printf("'%s' ", k)
		fmt.println()

		fmt.panicf("Level '%s' not found in map!", game_state.cur_level)
	}

	return level_ptr
}
