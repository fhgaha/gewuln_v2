package core

import r "vendor:raylib"

Interactable :: struct {
	name:   string,
	model:  r.Model,
	action: proc(intr: Interactable),
}

draw_interactables :: proc(color: r.Color = r.RED) {
	for intr in interactables {
		r.DrawModelWires(intr.model, pos_from_transform(intr.model.transform), 1, color)
	}
}

