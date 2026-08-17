package gewuln

import "../packages/toml"
import "core:encoding/json"
import "core:fmt"
import "core:math"
import "core:math/rand"
import "core:slice"
import "core:strings"
import r "vendor:raylib"

Actor_State_Type :: enum {
	IDLE,
	WALK,
	INTERACT,
	DIALOGUE,
	STAIR,
}

Actor_State_Type_strings := [Actor_State_Type]string {
	.IDLE     = "idle",
	.WALK     = "walk",
	.INTERACT = "interact",
	.DIALOGUE = "dialogue",
	.STAIR    = "stair",
}

Actor_State :: struct {
	type:        Actor_State_Type,
	transitions: []Actor_State_Transition,
	on_enter:    proc(),
	on_exit:     proc(),
}

Actor_State_Transition :: struct {
	from, to: Actor_State_Type,
	cond:     proc() -> bool,
}

actor_states := [Actor_State_Type]Actor_State {
	.IDLE = {
		type = .IDLE,
		transitions = []Actor_State_Transition {
			{.IDLE, .WALK, proc() -> bool {return input.move_dir != 0}},
			{
				.IDLE,
				.INTERACT,
				proc() -> bool {return(
						input.wants_interact &&
						main_actor_ctx.cur_interactable.interact_target_found \
					)},
			},
		},
	},
	.WALK = {
		type = .WALK,
		transitions = []Actor_State_Transition {
			{.WALK, .IDLE, proc() -> bool {return input.move_dir == 0}},
			{
				.WALK,
				.INTERACT,
				proc() -> bool {return(
						input.wants_interact &&
						main_actor_ctx.cur_interactable.interact_target_found \
					)},
			},
		},
	},
	.INTERACT = {
		type = .INTERACT,
		transitions = []Actor_State_Transition {
			{
				.INTERACT,
				.STAIR,
				proc() -> bool {return(
						main_actor_ctx.interact_state.interact_anim_ended &&
						main_actor_ctx.stair_state.stair_target_found \
					)},
			},
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
		},
	},
	.DIALOGUE = {
		type = .DIALOGUE,
		transitions = []Actor_State_Transition {
			{.DIALOGUE, .IDLE, proc() -> bool {return main_actor_ctx.dialogue_state.dialogue_ended}},
		},
	},
	.STAIR = {
		type = .STAIR,
		on_enter = proc() {
			main_actor_ctx.stair_state.stair_interactable =
				main_actor_ctx.intersected_interactables[0]
		},
	},
}

actor_transition_state :: proc(actor: ^Actor) {
	for &t in actor.state.transitions {
		if t.from == actor.state.type && t.cond() {
			actor_set_state(actor, t.to)
			return
		}
	}
}

actor_set_state :: proc(actor: ^Actor, new: Actor_State_Type) {
	if actor.state.type == new do return
	fmt.println(actor.name, "->", Actor_State_Type_strings[new])
	if actor.state.on_exit != nil do actor.state.on_exit()
	actor.state = actor_states[new]
	if actor.state.on_enter != nil do actor.state.on_enter()
}
