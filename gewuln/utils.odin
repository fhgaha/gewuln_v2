package gewuln

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

yaw_from_quat :: proc(q: r.Quaternion) -> f32 {
	return yaw_from_transform(r.QuaternionToMatrix(q))
}

yaw_from_direction :: proc(direction: vec3) -> f32 {
	return f32(math.atan2(f64(direction.x), f64(direction.z)) * r.RAD2DEG)
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
extract_tris :: proc(out: ^[dynamic]tri3, model: ^r.Model) {
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

print_pretty :: proc(args: ..any) {
	fmt.printf("here: %#v\n", args)
}

@(require_results)
must :: proc(val: $T, ok: bool, msg := "Value is not ok!", loc := #caller_location) -> T {
	if !ok do panic(msg, loc)
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
	r.Transform,
	bool,
) {
	for i in 0 ..< int(model.boneCount) {
		if i == bone_idx {
			return frame_poses[i], true
		}
	}
	return r.Transform{}, false
}
