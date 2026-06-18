package core

import "../packages/toml"
import "core:encoding/json"
import "core:fmt"
import "core:math"
import "core:strings"
import r "vendor:raylib"


Level :: struct {
	name:                      string,
	cam:                       ^r.Camera3D,
	cameras:                   map[string]r.Camera3D,
	room:                      r.Model,
	walk_area_mesh_idx:        i32,
	walk_area_tris:            [dynamic]tri3,
	interactables:             [dynamic]Interactable,
	spawn_positions:           [dynamic]Actor_Spawn_Placement,
	intersected_interactables: [dynamic]Interactable, //intersected by main actor
	actors:                    map[string]Actor, // all actors including main actor
}

Actor_Spawn_Placement :: struct {
	actor_name: string,
	pos:        vec3,
	yaw:        f32,
}

create_levels :: proc(
	toml_table: ^toml.Table,
) -> (
	levels: map[string]Level,
	first_level_name: string,
) {
	levels_table: ^toml.List
	ok: bool
	levels_table, ok = toml.get_list(toml_table, "levels"); assert(ok)
	first_level_name, ok = toml.get_string(toml_table, "first_level_name"); assert(ok)


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

	// dialogue text from config.toml

	// parse blender objects


	cameras: map[string]r.Camera3D
	interactables: [dynamic]Interactable
	walk_area_mesh_idx: i32 = -1
	walk_area_tris: [dynamic]tri3
	spawn_positions: [dynamic]Actor_Spawn_Placement
	actors := create_actors_from_toml(game_config)
	cur_cam_name: string

	room_glb_json := get_json_chunk_from_glb(room_glb_path)
	defer json.destroy_value(room_glb_json)
	cameras_json, cameras_json_ok := room_glb_json.(json.Object)["cameras"].(json.Array)

	for node in room_glb_json.(json.Object)["nodes"].(json.Array) {
		name_val := node.(json.Object)["name"]
		if name_val != nil {
			name := strings.to_lower(name_val.(json.String))

			is_camera := cameras_json_ok && strings.contains(name, "camera")
			if is_camera {
				cam_idx := node.(json.Object)["camera"].(json.Integer)
				cam_json := cameras_json[cam_idx].(json.Object)
				fovy := cam_json["perspective"].(json.Object)["yfov"].(json.Float) * r.RAD2DEG
				projection: r.CameraProjection
				switch cam_json["type"].(json.String) {
				case "perspective", "panoramic":
					projection = r.CameraProjection.PERSPECTIVE
				case "orthographic":
					projection = r.CameraProjection.ORTHOGRAPHIC
				}

				translation := parse_vec3_from_json(node.(json.Object), "translation")
				rotation := parse_quat_from_json(node.(json.Object), "rotation")
				forward := r.Vector3RotateByQuaternion(BACKWARD, rotation) // BACKWARD = {0, 0, -1}
				target := translation + forward

				cameras[name] = r.Camera3D {
					position   = translation,
					target     = target,
					up         = UP,
					fovy       = f32(fovy),
					projection = projection,
				}
				extras := node.(json.Object)["extras"]
				if extras != nil {
					if extras.(json.Object)["is_cur"].(json.Boolean) {
						cur_cam_name = name
					}
				}
			}

			is_interactable := strings.contains(name, "interactable")
			if is_interactable {
				intr := parse_interactable_from_glb(node.(json.Object))
				_, intr_type_is_dialogue := intr.data.(Dialogue_Data)
				if intr_type_is_dialogue {
					intr.data = parse_dialogue_from_toml(level_table)
				}
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
				extras := node.(json.Object)["extras"]
				actor_name: string
				if extras != nil {
					actor_name_ := extras.(json.Object)["actor_name"]
					if actor_name_ != nil {
						actor_name = actor_name_.(json.String)
					}
				}
				append(&spawn_positions, Actor_Spawn_Placement{actor_name, pos, yaw})
			}
		}
	}

	assert(cur_cam_name != "")
	cam := &cameras[cur_cam_name]


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

	// TODO second level wipes actors?
	for spawn in spawn_positions {
		actor_update_pos(&actors[spawn.actor_name], spawn.pos)
		actor_update_yaw(&actors[spawn.actor_name], spawn.yaw)
	}

	level := Level {
		name               = room_name,
		cam                = cam,
		cameras            = cameras,
		room               = room,
		walk_area_mesh_idx = walk_area_mesh_idx,
		walk_area_tris     = walk_area_tris,
		interactables      = interactables,
		spawn_positions    = spawn_positions,
		actors             = actors,
	}

	return level
}


destroy_level :: proc() {

}

load_level :: proc(lvl: ^Level) {
	// do this once at start in case actor appeared inside of interactable
	_, __ := get_interactable_colliding_actor(cur_level().interactables[:], main_actor)
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
