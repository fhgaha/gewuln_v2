package core

import r "vendor:raylib"

Interactable_Type :: enum {
	None,
	Door,
}

Door_Data :: struct {
	connected_level_name: string,
}

Interactable :: struct {
	name:  string,
	type:  Interactable_Type,
	model: r.Model,
	data:  union {
		Door_Data,
	},
}

@(private = "file")
Interactables_Naming_Table :: [?]struct {
	str:  string,
	type: Interactable_Type,
}{{"none", .None}, {"door", .Door}}


interact :: proc() {
	for intr in cur_level().intersected_intrs {
		switch dd in intr.data {
		case Door_Data:
			assert(dd.connected_level_name != "")
			assert(dd.connected_level_name in game_state.levels, "No such key in levels!")
			change_level(&game_state, &game_state.levels[dd.connected_level_name])
			break
		case:
		// no action or default
		}
	}
}

string_to_interactable :: proc(str: string) -> (Interactable_Type, bool) {
	for entry in Interactables_Naming_Table {
		if entry.str == str {
			return entry.type, true
		}
	}
	return .None, false
}

draw_interactables :: proc(color: r.Color = r.RED) {
	for intr in cur_level().interactables {
		r.DrawModelWires(intr.model, pos_from_transform(intr.model.transform), 1, color)
	}
}
