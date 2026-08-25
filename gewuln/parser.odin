package gewuln

import "../packages/toml"
import "core:encoding/json"
import "core:fmt"
import "core:math"
import "core:mem"
import "core:os"
import "core:strings"
import r "vendor:raylib"

parse_interactable_from_glb :: proc(node: json.Object, level_toml: ^toml.Table) -> Interactable {
	pos := parse_vec3_from_json(node, "translation")
	custom_props := node["extras"]
	data: Interactable_Data_Union
	if custom_props != nil {
		data = parse_interactable_data(custom_props.(json.Object), level_toml)
	}

	return Interactable {
		name       = strings.clone(node["name"].(json.String)),
		pos        = pos,
		mesh_index = -1, // these will be taken from loaded meshes
		data       = data,
	}
}

parse_interactable_data :: proc(
	node: json.Object,
	level_toml: ^toml.Table,
) -> Interactable_Data_Union {
	type_str, has_type := node["type"].(json.String)
	if !has_type do return nil

	switch type_str {
		case "door":
			connected, ok := node["connected_level"].(json.String)
			assert(ok)
			return Door_Data{connected_level_name = strings.clone(connected)}
		case "stair":
			connected, ok := node["connected_level"].(json.String)
			assert(ok)

			path_mesh_name: string
			if path_name, has_path := node["path"].(json.String); has_path {
				path_mesh_name = strings.clone(path_name)
			}

			return Stair_Data {
				connected_level_name = strings.clone(connected),
				path_mesh_name = path_mesh_name,
				path = {},
			}
		case "dialogue":
			dialogue_id := node["name"].(json.String)
			return parse_dialogue_from_toml(level_toml, dialogue_id)
		case:
	}
	return nil
}

parse_dialogue_from_toml :: proc(
	level_table: ^toml.Table,
	dialogue_name: string,
) -> Dialogue_Data {
	dialogues_list := toml.get_list_panic(level_table, "dialogues")

	for dialogue in dialogues_list {
		id := toml.get_string_panic(dialogue.(^toml.Table), "id")
		if id != dialogue_name do continue

		dd_lines: [dynamic]Dialogue_Line
		lines := toml.get_list_panic(dialogue.(^toml.Table), "lines")
		for line in lines {
			speaker_name := line.(^toml.List)[0].(string)
			text := line.(^toml.List)[1].(string)
			append(&dd_lines, Dialogue_Line{speaker_name, text})
		}

		return Dialogue_Data{lines = dd_lines[:]}
	}

	panic(fmt.tprintf("!no dialogue with id '%s' in level TOML", dialogue_name))
}

parse_vec3_from_json :: proc(node: json.Object, key: string) -> vec3 {
	tr := node[key]
	vector: vec3
	if tr != nil {
		for i in 0 ..< 3 {
			#partial switch v in tr.(json.Array)[i] {
				case json.Float: vector[i] = f32(v)
				case json.Integer: vector[i] = f32(v)
			}
		}
	}
	return vector
}

parse_quat_from_json :: proc(node: json.Object, key: string) -> r.Quaternion {
	tr := node[key]
	quat: r.Quaternion = r.Quaternion(1)
	if tr != nil {
		arr := tr.(json.Array)
		for i in 0 ..< 4 {
			val := arr[i]
			v: f32
			#partial switch w in val {
				case json.Float: v = f32(w)
				case json.Integer: v = f32(w)
			}
			switch i {
				case 0: quat.x = v
				case 1: quat.y = v
				case 2: quat.z = v
				case 3: quat.w = v
			}
		}
	}
	return quat
}

get_json_chunk_from_glb :: proc(glb_path: string) -> json.Value {
	data, ok := os.read_entire_file(glb_path)
	assert(ok, "couldnt read file")
	defer delete(data)

	// 4 bytes "glTF", 4 bytes version, 4 bytes glb length, 4 bytes json chunk length, 4 bytes "JSON".
	// each symbol is 1 byte. 20 bytes total before data

	chunk_length := mem.reinterpret_copy(u32, raw_data(data[12:16]))

	confirm_is_json, err := strings.clone_from_bytes(data[16:20])
	assert(confirm_is_json == "JSON" && err == .None)

	json_data := data[20:(20 + chunk_length)]

	parsed, parsed_err := json.parse(json_data, json.DEFAULT_SPECIFICATION, parse_integers = true)
	assert(parsed_err == .None)

	return parsed
}

parse_camera3d_from_glb :: proc(
	node: json.Object,
	cameras_json: ^json.Array,
) -> (
	camera: r.Camera3D,
	is_cur: bool,
) {
	cam_idx := node["camera"].(json.Integer)
	cam_json := cameras_json[cam_idx].(json.Object)
	fovy: f32
	projection: r.CameraProjection
	switch cam_json["type"].(json.String) {
		case "perspective", "panoramic":
			fovy = f32(cam_json["perspective"].(json.Object)["yfov"].(json.Float) * r.RAD2DEG)
			projection = r.CameraProjection.PERSPECTIVE
		case "orthographic": projection = r.CameraProjection.ORTHOGRAPHIC
	}

	translation := parse_vec3_from_json(node, "translation")
	rotation := parse_quat_from_json(node, "rotation")
	forward := r.Vector3RotateByQuaternion(BACKWARD, rotation) // BACKWARD = {0, 0, -1}
	target := translation + forward

	camera = r.Camera3D {
		position   = translation,
		target     = target,
		up         = UP,
		fovy       = fovy,
		projection = projection,
	}

	is_cur = node["extras"].(json.Object)["is_cur"].(json.Boolean)
	return
}
