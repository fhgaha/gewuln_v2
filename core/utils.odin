package core

import "core:encoding/json"
import "core:fmt"
import "core:math"
import "core:mem"
import "core:os"
import "core:strings"
import r "vendor:raylib"

//
// math
//
to_vec2 :: proc(v: vec3) -> vec2 {
	return vec2{v.x, v.z}
}

to_vec3 :: proc {
	vec2_to_vec3,
	vec4_to_vec3,
}

vec2_to_vec3 :: proc(v: vec2) -> vec3 {
	return vec3{v.x, 0, v.y}
}

vec4_to_vec3 :: proc(v: vec4) -> vec3 {
	return vec3{v.x, v.y, v.z}
}

to_vec4 :: proc(v: vec3) -> vec4 {
	return vec4{v.x, v.y, v.z, 1}
}

// wraps the angle to [0, 2PI] then shifts it to [-PI, PI]
clamp_angle :: proc(rad: f32) -> f32 {
	return rad - 2.0 * math.PI * math.floor((rad + math.PI) / (2.0 * math.PI))
}

vec3_lerp :: proc(a, b: vec3, t: f32) -> vec3 {
	return a + (b - a) * t
}

vec3_angle :: proc(v1: vec3, v2: vec3) -> f32 {
	// 1. Calculate the dot product
	dot := r.Vector3DotProduct(v1, v2)

	// 2. Calculate the magnitudes (lengths)
	len1 := r.Vector3Length(v1)
	len2 := r.Vector3Length(v2)

	// Prevent division by zero if a vector is empty
	if len1 == 0 || len2 == 0 do return 0

	cosTheta := math.clamp(dot / (len1 * len2), -1, 1)
	// 4. Return the angle in radians
	return math.acos_f32(cosTheta)
}

pos_from_transform :: proc(m: r.Matrix) -> vec3 {
	return vec3{m[0, 3], m[1, 3], m[2, 3]}
}

orientation_from_transform :: proc(m: r.Matrix) -> (fwd, left, up: vec3) {
	left = vec3{m[0, 0], m[1, 0], m[2, 0]}
	up = vec3{m[0, 1], m[1, 1], m[2, 1]}
	fwd = vec3{m[0, 2], m[1, 2], m[2, 2]}
	return
}

yaw_from_transform :: proc(m: r.Matrix) -> f32 {
	q := r.QuaternionFromMatrix(m)
	yaw := math.atan2(2 * (q.w * q.y + q.x * q.z), 1 - 2 * (q.x * q.x + q.y * q.y))
	return f32(yaw)
}

square_points_2d :: proc(min, max: vec2) -> [4]vec2 {
	return {
		min, // bottom-left
		{max.x, min.y}, // bottom-right
		max, // top-right
		{min.x, max.y}, // top-left
	}
}

check_collision_point_tris :: proc(point: vec2, tris: []tri2) -> bool {
	for t in tris {
		intersecting := r.CheckCollisionPointTriangle(point, t[0], t[1], t[2])
		if intersecting {
			return true
		}
	}
	return false
}

bounding_box_inside_walk_area :: proc(
	bounding_box: r.BoundingBox,
	walk_area_tris: []tri3,
) -> bool {
	bb_pts: [4]vec2 = square_points_2d(to_vec2(bounding_box.min), to_vec2(bounding_box.max))

	walk_area_tris_2d: [dynamic]tri2
	for t in walk_area_tris {
		t2: tri2 = {to_vec2(t[0]), to_vec2(t[1]), to_vec2(t[2])}
		append(&walk_area_tris_2d, t2)
	}

	pt0_intersects := check_collision_point_tris(bb_pts[0], walk_area_tris_2d[:])
	pt1_intersects := check_collision_point_tris(bb_pts[1], walk_area_tris_2d[:])
	pt2_intersects := check_collision_point_tris(bb_pts[2], walk_area_tris_2d[:])
	pt3_intersects := check_collision_point_tris(bb_pts[3], walk_area_tris_2d[:])

	return pt0_intersects && pt1_intersects && pt2_intersects && pt3_intersects
}

//
// meshes
//
extract_tris :: proc(model: ^r.Model, out: ^[dynamic]tri3) {
	tris: [dynamic]tri3
	defer delete(tris)

	for &m in model.meshes[:model.meshCount] {
		clear(&tris)
		extract_tris_from_mesh(&m, &tris)
		append(out, ..tris[:])
	}
}

extract_tris_from_mesh :: proc(m: ^r.Mesh, out: ^[dynamic]tri3) {
	cntr := 0
	a_tri: tri3
	//vertices are unique, each of them has format of [3]f32. indices are triangle indices, pointing to those vertices.
	for idx in m.indices[:m.triangleCount * 3] {
		//idx points where the thing start, then vertex has 3 components. so we get those 3 f32 numbers
		//then skip three numbers in the next cycle
		vert := vec3{m.vertices[idx * 3], m.vertices[idx * 3 + 1], m.vertices[idx * 3 + 2]}
		a_tri[cntr] = vert
		cntr += 1

		if cntr == 3 {
			append(out, a_tri)
			cntr = 0
		}
	}
}


Custom_Properties :: struct {
	actors_positions: [dynamic]Actor_Placement,
}

load_custom_props_from_glb :: proc(glb_path: string) -> Custom_Properties {
	json_data := get_json_chunk_from_glb(glb_path)
	defer json.destroy_value(json_data)

	actors_placements: [dynamic]Actor_Placement

	for node in json_data.(json.Object)["nodes"].(json.Array) {
		fill_actor_placements(&actors_placements, node, "spawn_pos")
	}

	// print(actors_placements)

	aps_mock: [dynamic]Actor_Placement
	append(&aps_mock, Actor_Placement{pos = vec3{1.5, 0, 2.0}, yaw = 0})

	// return Custom_Properties{actor_pos = transl, actor_yaw = yaw}
	return Custom_Properties{actors_positions = aps_mock}
}

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
	assert(ok)
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

//
// Helper to gather input in one place (e.g., in your main loop)
//
get_player_input :: proc() -> Input_State {
	return Input_State {
		move_dir = f32(i32(r.IsKeyDown(.W))) - f32(i32(r.IsKeyDown(.S))),
		turn_dir = f32(i32(r.IsKeyDown(.A))) - f32(i32(r.IsKeyDown(.D))),
		wants_interact = r.IsKeyPressed(.E),
	}
}

print :: proc(args: ..any) {
	fmt.println("here: ", args)
}

@(require_results)
must :: proc(val: $T, ok: bool, loc := #caller_location) -> T {
	if !ok do panic("Value is not ok!", loc)
	return val
}

DebugLine :: struct {
	start, end: vec3,
	color:      r.Color,
}

draw_debug_line :: proc(start, end: vec3, color: r.Color = r.RED) {
	append(&debug_lines, DebugLine{start, end, color})
}

get_bone_transform :: proc(
	model: ^r.Model,
	bone_idx: int,
	frame_poses: [^]r.Transform,
) -> (
	bool,
	r.Transform,
) {
	for i in 0 ..< int(model.boneCount) {
		if i == bone_idx {
			return true, frame_poses[i]
		}
	}
	return false, r.Transform{}
}
