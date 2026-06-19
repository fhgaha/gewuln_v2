package core

import "../packages/toml"
import "core:encoding/json"
import "core:fmt"
import "core:math"
import "core:mem"
import "core:os"
import "core:strings"
import r "vendor:raylib"

parse_interactable_from_glb :: proc(node: json.Object) -> Interactable {
	pos := parse_vec3_from_json(node, "translation")
	custom_props := node["extras"]
	data: Interactable_Data_Union
	if custom_props != nil {
		data = parse_interactable_type_from_json(custom_props.(json.Object))
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

parse_dialogue_from_toml :: proc(level_table: ^toml.Table) -> Dialogue_Data {
	dialogues_list := toml.get_list_panic(level_table, "dialogues")
	dd_lines: [dynamic]Dialogue_Line

	for elem in dialogues_list {
		id := toml.get_string_panic(elem.(^toml.Table), "id")
		lines := toml.get_list_panic(elem.(^toml.Table), "lines")
		for l, i in lines {
			dl := Dialogue_Line {
				toml.get_string_panic(l.(^toml.Table), "speaker"),
				toml.get_string_panic(l.(^toml.Table), "text"),
			}
			append(&dd_lines, dl)
		}
	}

	return Dialogue_Data{lines = dd_lines[:]}
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

parse_quat_from_json :: proc(node: json.Object, key: string) -> r.Quaternion {
	tr := node[key]
	quat: r.Quaternion = r.Quaternion(1)
	if tr != nil {
		arr := tr.(json.Array)
		for i in 0 ..< 4 {
			val := arr[i]
			v: f32
			#partial switch w in val {
			case json.Float:
				v = f32(w)
			case json.Integer:
				v = f32(w)
			}
			switch i {
			case 0:
				quat.x = v
			case 1:
				quat.y = v
			case 2:
				quat.z = v
			case 3:
				quat.w = v
			}
		}
	}
	return quat
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

parse_camera3d_from_glb :: proc(
	node: json.Object,
	cameras_json: ^json.Array,
) -> (
	camera: r.Camera3D,
	is_cur: bool,
) {
	cam_idx := node["camera"].(json.Integer)
	cam_json := cameras_json[cam_idx].(json.Object)
	fovy := cam_json["perspective"].(json.Object)["yfov"].(json.Float) * r.RAD2DEG
	projection: r.CameraProjection
	switch cam_json["type"].(json.String) {
	case "perspective", "panoramic":
		projection = r.CameraProjection.PERSPECTIVE
	case "orthographic":
		projection = r.CameraProjection.ORTHOGRAPHIC
	}

	translation := parse_vec3_from_json(node, "translation")
	rotation := parse_quat_from_json(node, "rotation")
	forward := r.Vector3RotateByQuaternion(BACKWARD, rotation) // BACKWARD = {0, 0, -1}
	target := translation + forward

	extras := node["extras"]
	is_cur = extras != nil && extras.(json.Object)["is_cur"].(json.Boolean) == true

	camera = r.Camera3D {
		position   = translation,
		target     = target,
		up         = UP,
		fovy       = f32(fovy),
		projection = projection,
	}
	return
}
