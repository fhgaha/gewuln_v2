package core

import "core:strings"
import r "vendor:raylib"

Interactable_Type :: enum {
	None,
	Door,
	Dialogue,
}

Door_Data :: struct {
	connected_level_name: string,
}

Dialogue_Data :: struct {
	lines:   []Dialogue_Line,
	cur_idx: int,
}

Dialogue_Line :: struct {
	speaker: string,
	text:    string,
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
	for intr in cur_level().intersected_interactables {
		switch d in intr.data {
		case Door_Data:
			assert(d.connected_level_name != "")
			assert(d.connected_level_name in game_state.levels, "No such key in levels!")
			change_level(&game_state, &game_state.levels[d.connected_level_name])
		case Dialogue_Data:
			second_actor := &cur_level().actors["cleaner_a"]
			run_dialogue(intr, main_actor, second_actor)
		case:
		// no action or default
		}
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

run_dialogue :: proc(intr: Interactable, main_actor: ^Actor, second_actor: ^Actor) {
	data := intr.data.(Dialogue_Data)
	// print_pretty(data)
	for l in data.lines {
		// here:  ["mona", "Hey, how's it going?"]
		// here:  ["cleaner_a", "Busy day. Floor's not gonna mop itself."]
		// here:  ["mona", "Fair enough."]
		// here:  ["cleaner_a", "..."]

		speaker := cur_level().actors[l.speaker]
		text := l.text

		r.DrawText(strings.clone_to_cstring(text), 20, 30, 16, r.WHITE)

	}
}
