package core

import r "vendor:raylib"

Interactable_Type :: enum {
	None,
	Door,
	Dialogue,
}

Door_Data :: struct {
	connected_level_name: string,
}

Dialogue_Data :: struct {}

Interactable_Data_Union :: union {
	Door_Data,
	Dialogue_Data,
}

Interactable :: struct {
	name:  string,
	type:  Interactable_Type,
	model: r.Model,
	data:  Interactable_Data_Union,
}

@(private = "file")
Interactables_Naming_Table :: [?]struct {
	str:  string,
	type: Interactable_Type,
}{{"none", .None}, {"door", .Door}, {"dialogue", .Dialogue}}


interact :: proc() {
	for intr in cur_level().intersected_intractables {
		switch d in intr.data {
		case Door_Data:
			assert(d.connected_level_name != "")
			assert(d.connected_level_name in game_state.levels, "No such key in levels!")
			change_level(&game_state, &game_state.levels[d.connected_level_name])
		case Dialogue_Data:

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
