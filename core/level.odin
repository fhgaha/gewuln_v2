package core

import "../packages/toml"
import "core:encoding/json"
import "core:fmt"
import "core:math"
import "core:mem"
import "core:os"
import "core:slice"
import "core:strings"
import r "vendor:raylib"


Level :: struct {
	name:                      string,
	cam:                       r.Camera3D,
	room:                      r.Model,
	walk_area_mesh_idx:        i32,
	walk_area_tris:            [dynamic]tri3,
	interactables:             [dynamic]Interactable,
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
	levels_table: ^toml.List
	ok: bool
	levels_table, ok = toml.get_list(section, "levels"); assert(ok)
	first_level_name, ok = toml.get_string(section, "first_level_name"); assert(ok)

	for lvl_table, i in levels_table {
		lvl := create_level(lvl_table.(^toml.Table))
		levels[lvl.name] = lvl
	}
	return
}

create_level :: proc(level_table: ^toml.Table) -> Level {

	// room

	room_name := must(toml.get_string(level_table, "name"))
	room_glb_path := must(toml.get_string(level_table, "room_glb"))
	room := r.LoadModel(strings.clone_to_cstring(room_glb_path))

	// interactables

	interactables: [dynamic]Interactable
	walk_area_mesh_idx: i32 = -1
	walk_area_tris: [dynamic]tri3

	room_glb_json := get_json_chunk_from_glb(room_glb_path)
	defer json.destroy_value(room_glb_json)
	for node in room_glb_json.(json.Object)["nodes"].(json.Array) {
		name_val := node.(json.Object)["name"]
		if name_val != nil {
			name := strings.to_lower(name_val.(json.String))
			is_interactable := strings.contains(name, "interactable")
			if is_interactable {
				intr := parse_interactable_from_json(node.(json.Object))
				append(&interactables, intr)
			}
			// print_pretty(name)

			is_walk_area := strings.contains(name, "walk_area")
			if is_walk_area {
				mesh_idx_raw := node.(json.Object)["mesh"].(json.Integer)
				walk_area_mesh_idx = i32(mesh_idx_raw)
				extract_tris_from_mesh(&room.meshes[walk_area_mesh_idx], &walk_area_tris)
			}
		}
	}
	// set mesh idx for intereactables
	for i in 0 ..< room.meshCount {
		m := room.meshes[i]
		bb := r.GetMeshBoundingBox(m)
		center := (bb.min + bb.max) * 0.5

		for &intr in interactables {
			if intr.mesh_index != -1 do continue
			if r.Vector3Distance(center, intr.pos) >= 0.1 do continue
			intr.mesh_index = i32(i)
		}
	}
	for intr in interactables {
		assert(intr.mesh_index != -1, "interactable not matched to any mesh")
	}

	// custom props
	// should be proc probably
	assert(main_actor.initialised, "actor must be initialised before placing it into a room")
	custom_props := load_custom_props_from_glb(room_glb_path)


	level := Level {
		name = room_name,
		cam = r.Camera3D {
			position = vec3{0, 4, 10},
			target = vec3{0, 0, -10},
			up = UP,
			fovy = FOV_DEG / 2,
			projection = .PERSPECTIVE,
		},
		room = room,
		walk_area_mesh_idx = walk_area_mesh_idx,
		walk_area_tris = walk_area_tris,
		interactables = interactables,
		actors_places = custom_props.actors_positions,
	}

	return level
}

parse_interactable_from_json :: proc(node: json.Object) -> Interactable {
	pos := parse_vec3_from_json(node, "translation")
	custom_props := node["extras"].(json.Object)
	data: Interactable_Data_Union
	if custom_props != nil {
		data = parse_interactable_type_from_json(custom_props)
	}

	return Interactable {
		name       = node["name"].(json.String),
		pos        = pos,
		mesh_index = -1, // these will be taken from loaded meshes
		data       = data,
	}
}

parse_interactable_type_from_json :: proc(node: json.Object) -> Interactable_Data_Union {
	type_str, has_type := node["type"].(json.String)
	if !has_type {return nil}
	switch type_str {
	case "door":
		connected := node["connected_level"].(json.String)
		return Door_Data{connected_level_name = connected}
	case "dialogue":
		return Dialogue_Data{}
	}
	return nil
}

parse_vec3_from_json :: proc(node: json.Object, key: string) -> vec3 {
	tr := node["translation"]
	vector: vec3
	if tr != nil {
		for i in 0 ..< 3 {
			#partial switch v in tr.(json.Array)[i] {
			case json.Float:
				vector[i] = f32(v)
			case json.Integer:
				vector[i] = f32(v)
			}
		}
	}
	return vector
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

Custom_Properties :: struct {
	actors_positions: [dynamic]Actor_Placement,
}

load_custom_props_from_glb :: proc(glb_path: string) -> Custom_Properties {
	json_data := get_json_chunk_from_glb(glb_path)
	defer json.destroy_value(json_data)

	actors_placements: [dynamic]Actor_Placement

	for node in json_data.(json.Object)["nodes"].(json.Array) {
		// shouldnt use this. just load levels with characters placed
		fill_actor_placements(&actors_placements, node, "spawn_pos")
	}

	// print(actors_placements)

	aps_mock: [dynamic]Actor_Placement
	append(&aps_mock, Actor_Placement{pos = vec3{1.5, 0, 2.0}, yaw = 0})

	// return Custom_Properties{actor_pos = transl, actor_yaw = yaw}
	return Custom_Properties{actors_positions = aps_mock}
}

// shouldnt use this. just load levels with characters placed
@(private = "file")
fill_actor_placements :: proc(
	actors_placements_to_fill: ^[dynamic]Actor_Placement,
	node: json.Value,
	value: string,
) {
	value_ := strings.to_lower(value)
	name_value := node.(json.Object)["name"].(json.String)
	name_value_ := strings.to_lower(name_value)
	if strings.contains(name_value, value_) {
		ap: Actor_Placement

		tr := node.(json.Object)["translation"]
		if tr != nil {
			for i in 0 ..< 3 {
				#partial switch v in tr.(json.Array)[i] {
				case json.Float:
					ap.pos[i] = f32(v)
				case json.Integer:
					ap.pos[i] = f32(v)
				}
			}
		}

		// glb uses quaternions for rotations: "rotation":[0,0.7071068286895752,0,0.7071068286895752],
		rot_val := node.(json.Object)["rotation"]
		quat: [4]f32
		if rot_val != nil {
			for i in 0 ..< 4 {
				#partial switch v in rot_val.(json.Array)[i] {
				case json.Float:
					quat[i] = f32(v)
				case json.Integer:
					quat[i] = f32(v)
				}
			}
		}

		ap.yaw = math.atan2(
			2 * (quat.w * quat.y + quat.x * quat.z),
			1 - 2 * (quat.x * quat.x + quat.y * quat.y),
		)

		append(actors_placements_to_fill, ap)
	}
}


get_json_chunk_from_glb :: proc(glb_path: string) -> json.Value {
	data, ok := os.read_entire_file(glb_path)
	assert(ok, "couldnt read file")
	defer delete(data)

	// 4 bytes "glTF", 4 bytes version, 4 bytes glb length, 4 bytes json chunk length, 4 bytes "JSON". each symbol is 1 byte

	// Cast a slice of bytes directly to a slice of u32, then take the first element
	chunk_length := mem.reinterpret_copy(u32, raw_data(data[12:16]))
	// chunk_type: u32 = mem.slice_data_cast([]u32, data[16:20])[0]

	res, err := strings.clone_from_bytes(data[16:20])
	assert(res == "JSON" && err == .None)

	json_data := data[20:(20 + chunk_length)]

	parsed, parsed_err := json.parse(json_data, json.DEFAULT_SPECIFICATION, parse_integers = true)
	assert(parsed_err == .None)

	return parsed
}
