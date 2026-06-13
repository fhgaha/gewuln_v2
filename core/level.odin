package core

import "../packages/toml"
import "core:fmt"
import "core:mem"
import "core:strings"
import r "vendor:raylib"


Level :: struct {
	name:                      string,
	cam:                       r.Camera3D,
	room:                      r.Model,
	walk_area:                 r.Model,
	walk_area_tris:            [dynamic]tri3,
	interactables:             [dynamic]Interactable,
	// actor:                    struct {
	// 	pos: vec3,
	// 	yaw: f32,
	// },
	actors_places:             [dynamic]Actor_Placement,
	intersected_interactables: [dynamic]Interactable, //currently colliding with main actor interactables
}

Actor_Placement :: struct {
	pos: vec3,
	yaw: f32,
}

create_levels :: proc(
	section: ^toml.Table,
) -> (
	levels: map[string]Level,
	first_level_name: string,
) {
	levels_table, ok2 := toml.get_list(section, "levels"); assert(ok2)

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
		intr_type, ok := string_to_interactable(
			must(toml.get_string(intr_fields_table, "type")),
		); assert(ok)
		glb_toml_cstr := strings.clone_to_cstring(must(toml.get_string(intr_fields_table, "glb")))
		data_table := must(toml.get_table(intr_fields_table, "data"))

		intr_data: Interactable_Data_Union

		switch intr_type {
		case .None:
		case .Door:
			intr_data = Door_Data {
				connected_level_name = must(toml.get_string(data_table, "connected_lvl_name")),
			}
		case .Dialogue:
		case:
		}

		append(
			&interactables,
			Interactable {
				name = intr_name_str,
				type = intr_type,
				model = r.LoadModel(glb_toml_cstr),
				data = intr_data,
			},
		)
		delete(glb_toml_cstr)
	}

	// custom props

	assert(main_actor.initialised, "actor must be initialised before placing it into a room")
	custom_props := load_custom_props_from_glb(room_glb_str)


	level := Level {
		name = room_name,
		cam = r.Camera3D {
			position = cam_pos,
			target = cam_target,
			up = UP,
			fovy = FOV_DEG / 2,
			projection = .PERSPECTIVE,
		},
		room = room,
		walk_area = walk_area,
		walk_area_tris = walk_area_tris,
		interactables = interactables,
		actors_places = custom_props.actors_positions,
	}

	return level
}

destroy_level :: proc() {

}

load_level :: proc(lvl: ^Level) {
	// do this once at start in case actor appeared inside of interactable
	_, __ := get_interactable_colliding_actor(cur_level().interactables[:], &main_actor)
}

unload_level :: proc(lvl: ^Level) {

}

change_level :: proc(state: ^Game_State, next: ^Level) {
	unload_level(cur_level())
	load_level(next)
	state.cur_level_name = next.name
}

cur_level :: proc() -> ^Level {
	level_ptr, ok := &game_state.levels[game_state.cur_level_name]
	if !ok {
		fmt.print("Available levels: ")
		for k, _ in game_state.levels do fmt.printf("'%s' ", k)
		fmt.println()

		fmt.panicf("Level '%s' not found in map!", game_state.cur_level_name)
	}

	return level_ptr
}
