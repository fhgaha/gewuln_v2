package core

import "core:slice"
import r "vendor:raylib"

Interactable_Type :: enum {
	None,
	Door,
	Dialogue,
}

Door_Data :: struct {
	connected_level_name: string,
}

Interactable_Data_Union :: union {
	Door_Data,
	Dialogue_Data,
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
}{{"none", .None}, {"door", .Door}, {"dialogue", .Dialogue}}


interact :: proc() {
	switch d in slice.last(interact_targets[:]).data {
	case Door_Data:
		assert(d.connected_level_name != "")
		assert(d.connected_level_name in game_state.levels, "No such key in levels!")
		change_level(&game_state, &game_state.levels[d.connected_level_name])
	case Dialogue_Data:
		second_actor := &cur_level().actors["cleaner_a"]
		main_actor.state = .DIALOGUE
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
