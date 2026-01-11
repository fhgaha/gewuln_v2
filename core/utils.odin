package core

import r "vendor:raylib"


//math
to_vec4 :: proc(v: vec3) -> vec4 {
	return vec4{v.x, v.y, v.z, 1}
}

to_vec3 :: proc(v: vec4) -> vec3 {
	return vec3{v.x, v.y, v.z}
}

//meshes
extract_tris :: proc(model: ^r.Model, out: ^[dynamic]tri) {
	tris: [dynamic]tri
	defer delete(tris)

	for &m in model.meshes[:model.meshCount] {
		clear(&tris)
		extract_tris_from_mesh(&m, &tris)
		for t in tris {
			append(out, t)
		}
	}
}

extract_tris_from_mesh :: proc(m: ^r.Mesh, out: ^[dynamic]tri) {
	cntr := 0
	a_tri: tri
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
