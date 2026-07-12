package core

import "../packages/toml"
import "core:encoding/json"
import "core:fmt"
import "core:math"
import "core:strings"
import r "vendor:raylib"

Level :: struct {
	name:                                     string,
	cam:                                      ^r.Camera3D,
	cameras:                                  map[string]r.Camera3D,
	room:                                     r.Model,
	walk_area_mesh_idx:                       i32,
	walk_area_tris:                           [dynamic]tri3,
	spawn_positions:                          [dynamic]Actor_Spawn_Placement,
	interactables, intersected_interactables: [dynamic]Interactable, //intersected by main actor
	actors:                                   map[string]Actor, // all actors including main actor
}

Actor_Spawn_Placement :: struct {
	actor_name: string,
	pos:        vec3,
	yaw:        f32,
}

create_levels :: proc(
	config_toml: ^toml.Table,
) -> (
	levels: map[string]Level,
	first_level_name: string,
) {
	levels_table: ^toml.List
	ok: bool
	levels_table, ok = toml.get_list(config_toml, "levels"); assert(ok)
	first_level_name, ok = toml.get_string(config_toml, "first_level_name"); assert(ok)

	actors := create_actors_from_toml(game_config)

	for lvl_table, i in levels_table {
		lvl := create_level(lvl_table.(^toml.Table), actors)
		levels[lvl.name] = lvl
	}
	return
}

found_main_actor: bool

create_level :: proc(level_toml: ^toml.Table, all_actors: map[string]Actor) -> Level {

	// room

	room_name := must(toml.get_string(level_toml, "name"))
	room_glb_path := must(toml.get_string(level_toml, "room_glb"))
	room := r.LoadModel(strings.clone_to_cstring(room_glb_path))


	// parse blender objects

	gameplay_cameras: map[string]r.Camera3D
	interactables: [dynamic]Interactable
	walk_area_mesh_idx: i32 = -1
	walk_area_tris: [dynamic]tri3
	spawn_positions: [dynamic]Actor_Spawn_Placement
	cur_cam_name: string

	room_glb_json := get_json_chunk_from_glb(room_glb_path)
	defer json.destroy_value(room_glb_json)
	cameras_json, cameras_json_ok := room_glb_json.(json.Object)["cameras"].(json.Array)
	assert(cameras_json_ok, "level must have a camera")

	for node in room_glb_json.(json.Object)["nodes"].(json.Array) {
		name_val := node.(json.Object)["name"]
		if name_val != nil {
			name := strings.to_lower(name_val.(json.String))

			is_camera := cameras_json_ok && strings.contains(name, "camera")
			if is_camera {
				camera, is_cur := parse_camera3d_from_glb(node.(json.Object), &cameras_json)
				if is_cur {
					cur_cam_name = name
				}
				assert(
					strings.contains(name, "gameplay"),
					"camera must contain \"gameplay\" in the name",
				)
				gameplay_cameras[name] = camera
			}

			is_interactable := strings.contains(name, "interactable")
			if is_interactable {
				intr := parse_interactable_from_glb(node.(json.Object), level_toml)

				// _, intr_type_is_dialogue := intr.data.(Dialogue_Data)
				// if intr_type_is_dialogue {
				// 	intr.data = parse_dialogue_from_toml(level_toml)
				// }

				append(&interactables, intr)
			}

			is_walk_area := strings.contains(name, "walk_area")
			if is_walk_area {
				mesh_idx_raw := node.(json.Object)["mesh"].(json.Integer)
				walk_area_mesh_idx = i32(mesh_idx_raw)
				extract_tris_from_mesh(&room.meshes[walk_area_mesh_idx], &walk_area_tris)
			}

			is_spawn_pos := strings.contains(name, "spawn_pos")
			if is_spawn_pos {
				pos := parse_vec3_from_json(node.(json.Object), "translation")
				rot := parse_quat_from_json(node.(json.Object), "rotation")
				yaw := yaw_from_quat(rot)
				extras, extras_ok := node.(json.Object)["extras"]
				assert(extras_ok)
				actor_name: string
				if extras != nil {
					actor_name_, an_ok := extras.(json.Object)["actor_name"]
					assert(an_ok)
					actor_name = actor_name_.(json.String)
				}
				append(&spawn_positions, Actor_Spawn_Placement{actor_name, pos, yaw})
			}
		}
	}

	assert(cur_cam_name != "", cur_cam_name)
	cam := &gameplay_cameras[cur_cam_name]

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

	level_actors: map[string]Actor
	for spawn in spawn_positions {
		if spawn.actor_name == "mona" && found_main_actor do continue
		if spawn.actor_name == "mona" && !found_main_actor do found_main_actor = true
		level_actors[spawn.actor_name] = all_actors[spawn.actor_name]
		actor_update_pos_and_yaw(&level_actors[spawn.actor_name], spawn.pos, spawn.yaw)
	}

	// TODO check everything nessesery is initialized

	level := Level {
		name               = room_name,
		cam                = cam,
		cameras            = gameplay_cameras,
		room               = room,
		walk_area_mesh_idx = walk_area_mesh_idx,
		walk_area_tris     = walk_area_tris,
		interactables      = interactables,
		spawn_positions    = spawn_positions,
		actors             = level_actors,
	}

	return level
}


destroy_level :: proc() {

}

load_level :: proc(lvl: ^Level) {

}

unload_level :: proc(lvl: ^Level) {

}

change_level :: proc(state: ^Game_State, next: ^Level) {
	// for _, actor in cur_level().actors {
	// 	print(cur_level().name, actor.name)
	// }

	unload_level(cur_level())
	state.cur_level_name = next.name
	load_level(next)

	// for _, actor in cur_level().actors {
	// 	print(cur_level().name, actor.name)
	// }
}

cur_level :: proc() -> ^Level {
	level_ptr, ok := &levels[game_state.cur_level_name]
	if !ok {
		fmt.print("Available levels: ")
		for k, _ in levels do fmt.printf("'%s' ", k)
		fmt.println()

		fmt.panicf("Level '%s' not found in map!", game_state.cur_level_name)
	}

	return level_ptr
}

get_interactable_mesh :: proc(interactable: ^Interactable) -> r.Mesh {
	return cur_level().room.meshes[interactable.mesh_index]
}

// shouldnt use this. just load levels with characters placed
@(private = "file")
fill_actor_placements :: proc(
	actors_placements_to_fill: ^[dynamic]Actor_Spawn_Placement,
	node: json.Value,
	value: string,
) {
	value_ := strings.to_lower(value)
	name_value := node.(json.Object)["name"].(json.String)
	name_value_ := strings.to_lower(name_value)
	if strings.contains(name_value, value_) {
		ap: Actor_Spawn_Placement

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
