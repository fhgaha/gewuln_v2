package core

import "core:fmt"
import r "vendor:raylib"


//math
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

pos_from_transform :: proc(m: r.Matrix) -> vec3 {
	return vec3{m[0, 3], m[1, 3], m[2, 3]}
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


//meshes
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
