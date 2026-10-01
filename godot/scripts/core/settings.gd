extends Node
## Persistent player settings (BRIEF §14) and the input map. Autoloaded as `Settings`.
## Voice, subtitle and UI languages are independent. Command-line user args (after `--`)
## override any key, e.g. `-- --quality=low --hour=17.5`; the harness relies on this.

signal changed

const PATH := "user://settings.cfg"
const QUALITY := {
	"low": {"shadows": false, "ssao": false, "ssil": false, "glow": true, "sdfgi": false, "volumetric": false, "render_scale": 0.75, "shadow_size": 2048, "near_r": 260.0, "far_r": 900.0},
	"medium": {"shadows": true, "ssao": true, "ssil": false, "glow": true, "sdfgi": false, "volumetric": false, "render_scale": 1.0, "shadow_size": 4096, "near_r": 300.0, "far_r": 1100.0},
	"high": {"shadows": true, "ssao": true, "ssil": true, "glow": true, "sdfgi": false, "volumetric": true, "render_scale": 1.0, "shadow_size": 4096, "near_r": 340.0, "far_r": 1400.0},
	"ultra": {"shadows": true, "ssao": true, "ssil": true, "glow": true, "sdfgi": true, "volumetric": true, "render_scale": 1.0, "shadow_size": 8192, "near_r": 420.0, "far_r": 1800.0},
}

var data := {
	"voice_lang": "ta", "subtitle_lang": "en", "ui_lang": "en", "city": "chennai",
	"camera": "third", "fov": 62.0, "quality": "high",
	"npc_density": 1.0, "traffic_density": 1.0, "horn_intensity": 1.0,
	"subtitle_size": 1.0, "colorblind": "none", "radio": true,
	"master_volume": 0.8, "music_volume": 0.7, "debug": true,
	"mouse_sens": 0.0025, "invert_y": false,
}
## cmdline args that are not settings (shot=, cam=, hour=, ...)
var args := {}

func _ready() -> void:
	_load()
	for a in OS.get_cmdline_user_args():
		var s: String = a.trim_prefix("--")
		var k := s.get_slice("=", 0)
		var v := s.substr(k.length() + 1) if s.contains("=") else "1"
		if data.has(k):
			var d = data[k]
			data[k] = float(v) if d is float else (v == "1" or v == "true") if d is bool else v
		else:
			args[k] = v
	_apply_quality()
	_build_input_map()

func get_v(k: String, def = null):
	return data.get(k, def)

func set_v(k: String, v) -> void:
	data[k] = v
	if k == "quality": _apply_quality()
	save()
	changed.emit()

func q(k: String):
	return data.get("q_" + k)

func _apply_quality() -> void:
	var p: Dictionary = QUALITY.get(data.quality, QUALITY.high)
	for k in p: data["q_" + k] = p[k]

func has_arg(k: String) -> bool:
	return args.has(k)

func arg(k: String, def := "") -> String:
	return args.get(k, def)

func arg_f(k: String, def := 0.0) -> float:
	return float(args[k]) if args.has(k) else def

func arg_vec(k: String) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	if args.has(k):
		for s in String(args[k]).split(","): out.append(float(s))
	return out

func save() -> void:
	if args.has("shot"): return # harness runs never persist
	var cf := ConfigFile.new()
	for k in data:
		if not k.begins_with("q_"): cf.set_value("settings", k, data[k])
	cf.save(PATH)

func _load() -> void:
	var cf := ConfigFile.new()
	if cf.load(PATH) == OK:
		for k in cf.get_section_keys("settings"):
			if data.has(k): data[k] = cf.get_value("settings", k)

# --------------------------------------------------------------------------------------------- input
const BINDINGS := {
	"move_forward": [KEY_W, KEY_UP], "move_back": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
	"sprint": [KEY_SHIFT], "jump": [KEY_SPACE], "walk": [KEY_ALT],
	"interact": [KEY_F, KEY_ENTER], "camera_cycle": [KEY_C], "horn": [KEY_H],
	"handbrake": [KEY_SPACE], "look_back": [KEY_V], "pause": [KEY_ESCAPE],
	"time_fwd": [KEY_BRACKETRIGHT], "time_back": [KEY_BRACKETLEFT], "debug_toggle": [KEY_F3],
	"radio_next": [KEY_R],
}
const PAD_BUTTONS := {
	"jump": [JOY_BUTTON_A], "interact": [JOY_BUTTON_Y], "camera_cycle": [JOY_BUTTON_BACK],
	"sprint": [JOY_BUTTON_B], "horn": [JOY_BUTTON_LEFT_STICK], "handbrake": [JOY_BUTTON_RIGHT_SHOULDER],
	"pause": [JOY_BUTTON_START], "radio_next": [JOY_BUTTON_DPAD_RIGHT],
}
const PAD_AXES := {
	"move_forward": [JOY_AXIS_LEFT_Y, -1.0], "move_back": [JOY_AXIS_LEFT_Y, 1.0],
	"move_left": [JOY_AXIS_LEFT_X, -1.0], "move_right": [JOY_AXIS_LEFT_X, 1.0],
	"look_left": [JOY_AXIS_RIGHT_X, -1.0], "look_right": [JOY_AXIS_RIGHT_X, 1.0],
	"look_up": [JOY_AXIS_RIGHT_Y, -1.0], "look_down": [JOY_AXIS_RIGHT_Y, 1.0],
	"throttle": [JOY_AXIS_TRIGGER_RIGHT, 1.0], "brake": [JOY_AXIS_TRIGGER_LEFT, 1.0],
}

func _build_input_map() -> void:
	var names := {}
	for k in BINDINGS: names[k] = true
	for k in PAD_BUTTONS: names[k] = true
	for k in PAD_AXES: names[k] = true
	for action in names:
		if not InputMap.has_action(action): InputMap.add_action(action, 0.2)
		for key in BINDINGS.get(action, []):
			var e := InputEventKey.new(); e.physical_keycode = key; InputMap.action_add_event(action, e)
		for b in PAD_BUTTONS.get(action, []):
			var e := InputEventJoypadButton.new(); e.button_index = b; InputMap.action_add_event(action, e)
		if PAD_AXES.has(action):
			var e := InputEventJoypadMotion.new(); e.axis = PAD_AXES[action][0]; e.axis_value = PAD_AXES[action][1]
			InputMap.action_add_event(action, e)
