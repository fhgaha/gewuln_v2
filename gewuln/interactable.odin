package gewuln

import "core:fmt"
import "core:slice"
import "core:strings"
import r "vendor:raylib"

Interactable_Type :: enum {
	None,
	Door,
	Dialogue,
	Stair,
}

Door_Data :: struct {
	connected_level_name: string,
}

Stair_Data :: struct {
	connected_level_name: string,
	path_mesh_name:       string, // name of the path node in the glb, from extras["path"]
	path:                 []vec3,
	cur_path_point_idx:   int,
}

Interactable_Data_Union :: union {
	Door_Data,
	Dialogue_Data,
	Stair_Data,
}

Interactable :: struct {
	name:       string,
	pos:        vec3,
	mesh_index: i32,
	data:       Interactable_Data_Union,
}

@(private = "file")
Interactables_Naming_Table :: [?]struct {
	str:  string,
	type: Interactable_Type,
}{{"none", .None}, {"door", .Door}, {"dialogue", .Dialogue}, {"stair", .Stair}}


interact :: proc() {
	switch d in main_actor_state.intersected_interactables[0].data {
	case Door_Data:
		assert(d.connected_level_name != "")
		assert(strings.contains(strings.to_lower(d.connected_level_name), "room"))
		// assert(
		// 	d.connected_level_name in levels,
		// 	fmt.tprintf("No such key in levels: %v", d.connected_level_name),
		// )
		change_level(&game_state, d.connected_level_name)

	case Dialogue_Data:
		// TODO mock
		second_actor := &cur_level().actors["cleaner_a"]
		main_actor.state = .DIALOGUE
	case Stair_Data:
		assert(d.connected_level_name != "")
		assert(strings.contains(strings.to_lower(d.connected_level_name), "room"))
		assert(len(d.path) > 0)

	//play walk stair animation
	//move up/down the stair
	//move to next room
	case:
	// no action or default
	}
}

string_to_interactable_type :: proc(str: string) -> (Interactable_Type, bool) {
	for entry in Interactables_Naming_Table {
		if entry.str == str {
			return entry.type, true
		}
	}
	return .None, false
}

get_interactable_center :: proc(interactable: ^Interactable) -> vec3 {
	bb := r.GetMeshBoundingBox(cur_level().room.meshes[interactable.mesh_index])
	return (bb.min + bb.max) * 0.5
}

is_interactable_mesh :: proc(interactables: []Interactable, mesh_index: i32) -> bool {
	for intr in interactables {
		if intr.mesh_index == mesh_index do return true
	}
	return false
}
