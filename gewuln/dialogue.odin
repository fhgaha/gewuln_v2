package gewuln

import r "vendor:raylib"

cur_dialogue: Dialogue_Data

Dialogue_Data :: struct {
	lines:      []Dialogue_Line,
	cur_idx:    int,
	cashed_cam: ^r.Camera3D,
}

Dialogue_Line :: struct {
	speaker: string,
	text:    string,
}

get_dialogue_speaker_name :: proc() -> string {
	return cur_dialogue.lines[cur_dialogue.cur_idx].speaker
}
get_dialogue_text :: proc() -> string {
	return cur_dialogue.lines[cur_dialogue.cur_idx].text
}
