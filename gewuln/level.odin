package gewuln

import "../packages/toml"
import "base:runtime"
import "core:encoding/json"
import "core:fmt"
import "core:math"
import "core:strings"
import r "vendor:raylib"

Level :: struct {
	name:               string,
	cam:                ^r.Camera3D,
	cameras:            map[string]r.Camera3D,
	room:               r.Model,
	walk_area_mesh_idx: i32,
	walk_area_tris:     [dynamic]tri3,
	interactables:      [dynamic]Interactable,
	actors:             map[string]Actor, // all actors including main actor
}

Actor_Spawn_Placement :: struct {
	actor_name: string,
	pos:        vec3,
	yaw:        f32,
}

load_level :: proc(state: ^Game_State, name: string) {
	state.cur_level_name = name

	next_lvl_data: Level_Data
	found: bool
	for lvl_data in levels_datas {
		if lvl_data.name == name {
			next_lvl_data = lvl_data
			found = true
			break
		}
	}
	assert(found, fmt.tprintf("Level '%s' not found!", name))

	level = create_level_from_level_data(next_lvl_data)
	level.actors = make(map[string]Actor)

	//fill level.actors
	for spawn in next_lvl_data.spawn_positions {
		if actor, ok := all_actors[spawn.actor_name]; ok {
			level.actors[spawn.actor_name] = actor
			actor_update_pos_and_yaw(&level.actors[spawn.actor_name], spawn.pos, spawn.yaw)
		} else {
			panic(fmt.tprintf("No such actor '%s'!", spawn.actor_name))
		}
	}

	main_actor = &cur_level().actors["mona"]
	for actor_name, &actor in level.actors {
		actor_update_pos(&actor, actor.pos)
	}
}

unload_level :: proc(lvl: ^Level) {
	err: runtime.Allocator_Error
	// delete(lvl.name)	// points to TOML table, dont delete
	// delete(lvl.cam)	// removed on exit or Level struct delete
	err = delete(lvl.cameras); assert(err == .None)
	r.UnloadModel(lvl.room)
	// delete(lvl.walk_area_mesh_idx)	// removed on exit or Level struct delete
	err = delete(lvl.walk_area_tris); assert(err == .None)
	err = delete(lvl.interactables); assert(err == .None)
	err = delete(lvl.actors); assert(err == .None)
}

change_level :: proc(state: ^Game_State, next: string) {
	assert(next != "")

	unload_level(cur_level())
	load_level(state, next)
}

cur_level :: proc() -> ^Level {
	return &level
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
	if strings.contains(name_value_, value_) {
		ap: Actor_Spawn_Placement

		tr := node.(json.Object)["translation"]
		if tr != nil {
			for i in 0 ..< 3 {
				#partial switch v in tr.(json.Array)[i] {
					case json.Float: ap.pos[i] = f32(v)
					case json.Integer: ap.pos[i] = f32(v)
				}
			}
		}

		// glb uses quaternions for rotations: "rotation":[0,0.7071068286895752,0,0.7071068286895752],
		rot_val := node.(json.Object)["rotation"]
		quat: [4]f32
		if rot_val != nil {
			for i in 0 ..< 4 {
				#partial switch v in rot_val.(json.Array)[i] {
					case json.Float: quat[i] = f32(v)
					case json.Integer: quat[i] = f32(v)
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


/*---------------------------------------------------------------*/
Level_Data :: struct {
	name:               string,
	cam:                ^r.Camera3D,
	cameras:            map[string]r.Camera3D,
	// room:                                     r.Model,
	model_path:         string,
	walk_area_mesh_idx: i32,
	walk_area_tris:     [dynamic]tri3,
	spawn_positions:    [dynamic]Actor_Spawn_Placement,
	interactables:      [dynamic]Interactable, //intersected by main actor
	// actors:                                   map[string]Actor, // all actors including main actor
}

create_levels_datas :: proc(config_toml: ^toml.Table) -> [dynamic]Level_Data {
	levels_toml: ^toml.List
	ok: bool
	levels_toml, ok = toml.get_list(config_toml, "levels"); assert(ok)

	levels_datas: [dynamic]Level_Data
	for lvl_toml in levels_toml {
		lvl_data := create_level_data(lvl_toml.(^toml.Table))
		append(&levels_datas, lvl_data)
	}

	return levels_datas
}

create_level_data :: proc(level_toml: ^toml.Table) -> Level_Data {
	room_name := must(toml.get_string(level_toml, "name"))
	room_glb_path := must(toml.get_string(level_toml, "room_glb"))
	room := r.LoadModel(strings.clone_to_cstring(room_glb_path))
	defer r.UnloadModel(room)

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
	nodes := room_glb_json.(json.Object)["nodes"].(json.Array)

	for node in nodes {
		name_val := node.(json.Object)["name"]
		if name_val != nil {
			name := strings.to_lower(name_val.(json.String))

			node_is_camera := cameras_json_ok && strings.contains(name, "camera")
			if node_is_camera {
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

			node_is_interactable := strings.contains(name, "interactable")
			if node_is_interactable {
				intr := parse_interactable_from_glb(node.(json.Object), level_toml)
				append(&interactables, intr)
			}

			node_is_walk_area := strings.contains(name, "walk_area")
			if node_is_walk_area {
				mesh_idx_raw := node.(json.Object)["mesh"].(json.Integer)
				walk_area_mesh_idx = i32(mesh_idx_raw)
				extract_tris_from_mesh(&room.meshes[walk_area_mesh_idx], &walk_area_tris)
			}

			node_is_spawn_pos := strings.contains(name, "spawn_pos")
			if node_is_spawn_pos {
				pos := parse_vec3_from_json(node.(json.Object), "translation")
				rot := parse_quat_from_json(node.(json.Object), "rotation")
				yaw := yaw_from_quat(rot)
				extras, extras_ok := node.(json.Object)["extras"]
				assert(extras_ok)
				actor_name: string
				if extras != nil {
					actor_name_, an_ok := extras.(json.Object)["actor_name"]
					assert(an_ok)
					actor_name = strings.clone(actor_name_.(json.String))
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
		fmt.assertf(intr.mesh_index != -1, "interactable '%s' not matched to any mesh", intr.name)
	}

	// get path points, store them in stair data
	for &intr in interactables {
		// intr = [Interactable{
		// 	name = "interactable.003",
		// 	pos = [2.6296787, 1.06871939, -7.1350298],
		// 	mesh_index = 7,
		// 	data = Stair_Data{
		// 		connected_level_name = "another_test_room",
		// 		path_mesh_name = "path.001",
		// 		path = [],
		// 		cur_path_point_idx = 0
		// 	}
		// }]
		path_points: [dynamic]vec3
		if stair_data, ok := &intr.data.(Stair_Data); ok {
			for path_node in nodes {
				node_name, has := path_node.(json.Object)["name"].(json.String)
				if has && node_name == stair_data.path_mesh_name {
					parent_origin := parse_vec3_from_json(path_node.(json.Object), "translation")

					if children_indeces, ok := path_node.(json.Object)["children"].(json.Array);
					   ok {
						// children = [[15, 16, 17]]
						for child_idx in children_indeces {
							child := nodes[child_idx.(json.Integer)].(json.Object)
							point := parse_vec3_from_json(child, "translation")
							point += parent_origin
							append(&path_points, point)
						}
						stair_data.path = path_points[:]
					}
				}
			}

			fmt.assertf(
				len(stair_data.path) > 0,
				"stair '%s': path node '%s' not found or empty",
				intr.name,
				stair_data.path_mesh_name,
			)
		}
	}


	// level_actors: map[string]Actor
	// for spawn in spawn_positions {
	// 	if spawn.actor_name == "mona" && found_main_actor do continue
	// 	if spawn.actor_name == "mona" && !found_main_actor do found_main_actor = true
	// 	level_actors[spawn.actor_name] = all_actors[spawn.actor_name]
	// 	actor_update_pos_and_yaw(&level_actors[spawn.actor_name], spawn.pos, spawn.yaw)
	// }


	return Level_Data {
		name = room_name,
		cam = cam,
		cameras = gameplay_cameras,
		model_path = room_glb_path,
		walk_area_mesh_idx = walk_area_mesh_idx,
		walk_area_tris = walk_area_tris,
		spawn_positions = spawn_positions,
		interactables = interactables,
	}
}

create_level_from_level_data :: proc(level_data: Level_Data) -> Level {
	return Level {
		name = level_data.name,
		cam = level_data.cam,
		cameras = level_data.cameras,
		room = r.LoadModel(strings.clone_to_cstring(level_data.model_path)),
		walk_area_mesh_idx = level_data.walk_area_mesh_idx,
		walk_area_tris = level_data.walk_area_tris,
		interactables = level_data.interactables,
	}
}
