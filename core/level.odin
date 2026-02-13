package core

import "../packages/toml"
import "core:fmt"
import "core:mem"
import "core:strings"
import r "vendor:raylib"


Level :: struct {
	name:           string,
	cam:            r.Camera3D,
	cam_mode:       r.CameraMode,
	room:           r.Model,
	walk_area:      r.Model,
	walk_area_tris: [dynamic]tri3,
	interactables:  [dynamic]Interactable,
}

create_levels :: proc(
	section: ^toml.Table,
) -> (
	levels: map[string]Level,
	first_level_name: string,
) {


	levels_table, ok2 := toml.get_list(section, "levels"); assert(ok2)

	print(section)

	ok1: bool
	first_level_name, ok1 = toml.get_string(section, "first_level_name"); assert(ok1)

	for lvl_table, i in levels_table {
		lvl := create_level(lvl_table.(^toml.Table))
		levels[lvl.name] = lvl
	}
	return
}

create_level :: proc(level_table: ^toml.Table) -> Level {

	// camera

	cam_pos_table := must(toml.get_list(level_table, "camera", "pos"))
	cam_pos: [3]f32
	for i in 0 ..< 3 {
		#partial switch v in cam_pos_table[i] {
		case i64:
		case f64:
			cam_pos[i] = f32(v)
		}
	}

	cam_target_table := must(toml.get_list(level_table, "camera", "target"))

	cam_target: [3]f32
	for i in 0 ..< 3 {
		#partial switch v in cam_target_table[i] {
		case i64:
		case f64:
			cam_target[i] = f32(v)
		}
	}

	// room

	room_name := must(toml.get_string(level_table, "name"))

	room_glb_str := must(toml.get_string(level_table, "room_glb"))
	room_glb_cstr := strings.clone_to_cstring(room_glb_str)
	room := r.LoadModel(room_glb_cstr)
	delete(room_glb_cstr)


	// walk area

	walk_area_glb_str := must(toml.get_string(level_table, "walk_area_glb"))
	walk_area_glb_cstr := strings.clone_to_cstring(walk_area_glb_str)
	walk_area := r.LoadModel(walk_area_glb_cstr)
	delete(walk_area_glb_cstr)


	walk_area_tris: [dynamic]tri3
	extract_tris(&walk_area, &walk_area_tris)
	// assert(len(walk_area_tris) > 0)

	// interactables

	interactables: [dynamic]Interactable

	interactables_table := must(toml.get_list(level_table, "interactables"))
	for intr in interactables_table {
		intr_fields_table := intr.(^toml.Table)
		intr_name_str := must(toml.get_string(intr_fields_table, "name"))
		intr_glb_str := must(toml.get_string(intr_fields_table, "glb"))

		glb_toml_cstr := strings.clone_to_cstring(intr_glb_str)
		append(
			&interactables,
			Interactable {
				name = intr_name_str,
				model = r.LoadModel(glb_toml_cstr),
				action = proc(intr: Interactable) {
					// fmt.printfln("action of %s", name_)
				},
			},
		)
		delete(glb_toml_cstr)
	}

	level := Level {
		name = room_name,
		cam = r.Camera3D {
			position = cam_pos,
			target = cam_target,
			up = UP,
			fovy = FOV_DEG / 2,
			projection = .PERSPECTIVE,
		},
		cam_mode = r.CameraMode.CUSTOM,
		room = room,
		walk_area = walk_area,
		walk_area_tris = walk_area_tris,
		interactables = interactables,
	}

	// custom props

	assert(main_actor.initialised, "actor must be initialised before placing it into a room")
	custom_props := load_custom_props_from_glb(room_glb_str)
	actor_pos_update(custom_props.actor_pos)
	main_actor.yaw = custom_props.actor_yaw
	main_actor.model.transform = r.MatrixRotateY(custom_props.actor_yaw)

	return level
}

destroy_level :: proc() {}

load_level :: proc(lvl: ^Level) {}

unload_level :: proc(lvl: ^Level) {
	cur_lvl := get_cur_level()

	r.UnloadModel(cur_lvl.walk_area)
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
