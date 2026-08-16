package gewuln

import "../packages/toml"
import "core:encoding/json"
import "core:fmt"
import "core:math"
import "core:math/rand"
import "core:slice"
import "core:strings"
import r "vendor:raylib"

Actor_State :: enum {
	IDLE,
	WALK,
	INTERACT,
	DIALOGUE,
	STAIR,
}

actor_state_strings := [Actor_State]string {
	.IDLE     = "idle",
	.WALK     = "walk",
	.INTERACT = "interact",
	.DIALOGUE = "dialogue",
	.STAIR    = "stair",
}

Actor_State_Transition :: struct {
	from, to: Actor_State,
	cond:     proc() -> bool,
}

actor_transitions := []Actor_State_Transition {
	//from, to, condition
	// IDLE
	{.IDLE, .WALK, proc() -> bool {return input.move_dir != 0}},
	{
		.IDLE,
		.INTERACT,
		proc() -> bool {return(
				input.wants_interact &&
				main_actor_ctx.cur_interactable.interact_target_found \
			)},
	},
	//
	// WALK
	{
		.WALK,
		.INTERACT,
		proc() -> bool {return(
				input.wants_interact &&
				main_actor_ctx.cur_interactable.interact_target_found \
			)},
	},
	{.WALK, .IDLE, proc() -> bool {return input.move_dir == 0}},
	{
		.INTERACT,
		.STAIR,
		proc() -> bool {
			// on enter
			main_actor_ctx.stair_state.stair_interactable =
				main_actor_ctx.intersected_interactables[0]

			return(
				main_actor_ctx.interact_state.interact_anim_ended &&
				main_actor_ctx.stair_state.stair_target_found \
			)
		},
	},
	//
	// INTERACT
	{
		.INTERACT,
		.DIALOGUE,
		proc() -> bool {return(
				main_actor_ctx.interact_state.interact_anim_ended &&
				main_actor_ctx.dialogue_state.dialogue_target_found \
			)},
	},
	{
		.INTERACT,
		.WALK,
		proc() -> bool {return(
				main_actor_ctx.interact_state.interact_anim_ended &&
				input.move_dir != 0 \
			)},
	},
	{.INTERACT, .IDLE, proc() -> bool {return main_actor_ctx.interact_state.interact_anim_ended}},
	//
	// DIALOGUE
	{.DIALOGUE, .IDLE, proc() -> bool {return main_actor_ctx.dialogue_state.dialogue_ended}},
}

actor_set_state :: proc(actor: ^Actor, new: Actor_State) {
	if actor.state == new do return
	fmt.println(actor.name, "->", actor_state_strings[new])
	actor.state = new
}

actor_transition_state :: proc(actor: ^Actor) {
	for &t in actor_transitions {
		if t.from == actor.state && t.cond() {
			actor_set_state(actor, t.to)
			return
		}
	}
}
