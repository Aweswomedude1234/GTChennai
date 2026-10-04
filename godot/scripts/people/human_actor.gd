class_name HumanActor
extends Node3D
## A realistic human: an MPFB body variant (godot/assets/humans/<id>.glb, built by
## tools/humans/build_humans.py) driven by the shared CMU mocap library (anims.glb), with per-person
## skin tone, garment colours/patterns and hair re-shaded at runtime so a handful of meshes become
## hundreds of distinct people (BRIEF §15: 200+ appearance combinations).

static var _specs: Array = []
static var _lib: AnimationLibrary
static var _scenes := {}
static var _mats := {}
const LOOPS := ["ride_cycle", "ride_bike", "ride_scooter", "ride_auto", "ride_pass", "ride_pillion", "walk", "walk_slow", "walk_brisk", "walk_alt", "run", "jog", "idle", "idle_alt", "talk", "argue", "drink_tea", "traffic_police"]
# natural ground speed of each locomotion clip (m/s) for matching playback speed
const CLIP_SPEED := {"walk_slow": 0.95, "walk": 1.35, "walk_brisk": 1.7, "jog": 3.0, "run": 4.8}

var spec: Dictionary
var app: Appearance
var model: Node3D
var player: AnimationPlayer
var skeleton: Skeleton3D
var current := ""
var speed := 0.0
var idle_clip := "idle"
var action := ""            # a one-shot / gesture clip overriding locomotion (e.g. "talk", "drink_tea")

static func specs() -> Array:
	if _specs.is_empty():
		var d = CityPack.load_json("res://assets/humans/bodies.json")
		_specs = d if d else []
	return _specs

static func library() -> AnimationLibrary:
	if _lib == null:
		var n: Node = load("res://assets/humans/anims.glb").instantiate()
		var ap: AnimationPlayer = n.find_child("AnimationPlayer", true, false)
		_lib = ap.get_animation_library("").duplicate(true)
		for a in _lib.get_animation_list():
			_lib.get_animation(a).loop_mode = Animation.LOOP_LINEAR if a in LOOPS else Animation.LOOP_NONE
		n.free()
	return _lib

static var _rides := {}
## seat a rider on a vehicle (riding clip + its hip point from assets/humans/rides.json)
func ride(clip: String, x_off := 0.0, off := Vector3.ZERO) -> void:
	if _rides.is_empty():
		var d = CityPack.load_json("res://assets/humans/rides.json")
		_rides = d if d else {}
	var h: Array = _rides.get(clip, {"hips": [0, 1, 0]}).hips
	position = Vector3(float(h[0]) + x_off, 0.0, float(h[2])) + off
	rotation = Vector3.ZERO
	action = clip
	_play(clip, 0.0)
	player.speed_scale = 1.0

## pick a body variant matching sex / age group / dress
static func pick_spec(r: Rng, sex := "", child := false, dress := "") -> Dictionary:
	var c: Array = []
	for s in specs():
		var is_child: bool = String(s.id).begins_with("child")
		if child != is_child: continue
		if sex != "" and s.sex != sex: continue
		if dress != "" and s.dress != dress: continue
		c.append(s)
	if c.is_empty(): c = specs()
	return r.pick(c)

func build(s: Dictionary, a: Appearance = null, seed := 1) -> void:
	spec = s
	var r := Rng.new(seed)
	var path := "res://assets/humans/%s.glb" % s.id
	if not _scenes.has(path): _scenes[path] = load(path)
	model = _scenes[path].instantiate()
	model.rotation.y = PI          # glTF bodies face +Z; Godot nodes face −Z
	add_child(model)
	skeleton = model.find_child("Skeleton3D", true, false)
	player = AnimationPlayer.new()
	player.name = "Anim"
	model.add_child(player)
	player.add_animation_library("", library())
	app = a if a else appearance_for(s, r)
	_shade(r)
	idle_clip = "idle" if r.next() < 0.6 else "idle_alt"
	_play(idle_clip, 0.0)
	player.seek(r.next() * 3.0, true)

## colours consistent with the variant's dress (Appearance palettes, STYLE_BIBLE §6)
static func appearance_for(s: Dictionary, r: Rng) -> Appearance:
	var a := Appearance.new()
	a.sex = s.sex
	a.skin = Color(Appearance.SKIN[r.pick_w(Appearance.SKIN_W)])
	a.hair = Color(r.pick(Appearance.HAIR_GREY)) if float(s.macro.age) > 0.78 and r.next() < 0.7 else Color(r.pick(Appearance.HAIR))
	match String(s.dress):
		"shirt_pants": a.top = Color(r.pick(Appearance.SHIRTS)); a.lower = Color(r.pick(Appearance.PANTS)); a.top_pattern = 1 if r.next() < 0.25 else (3 if r.next() < 0.1 else 0); a.lower_denim = r.next() < 0.45
		"tshirt_pants": a.top = Color(r.pick(Appearance.TSHIRTS)); a.lower = Color(r.pick(Appearance.PANTS)); a.lower_denim = r.next() < 0.65
		"shirt_veshti": a.top = Color(r.pick(Appearance.SHIRTS)) if r.next() < 0.7 else Color(r.pick(Appearance.VESHTI)); a.lower = Color(r.pick(Appearance.VESHTI)); a.border = Color(r.pick(Appearance.VESHTI_BORDER)); a.pattern = 2
		"shirt_lungi": a.top = Color(r.pick(Appearance.SHIRTS)); a.lower = Color(r.pick(Appearance.LUNGI)); a.border = Color(r.pick(Appearance.LUNGI)).darkened(0.3); a.pattern = 1
		"saree":
			a.lower = Color(r.pick(Appearance.SAREES)); a.drape = a.lower; a.border = Color(r.pick(Appearance.SAREE_BORDER)); a.pattern = 2
			a.top = Color(r.pick(Appearance.SAREES)) if r.next() < 0.5 else a.lower
			a.top_pattern = 4 if r.next() < 0.4 else 0
		"churidar": a.top = Color(r.pick(Appearance.KURTA)); a.lower = Color(r.pick(Appearance.LEGGINGS)); a.drape = Color(r.pick(Appearance.KURTA)); a.top_pattern = 4 if r.next() < 0.4 else 0
		"nighty": a.top = Color(r.pick(Appearance.KURTA)); a.top_pattern = 4
		"uniform_shorts", "uniform_skirt": a.top = Color(r.pick(Appearance.UNIFORM_SHIRT)); a.lower = Color(r.pick(Appearance.UNIFORM_LOWER))
		_: a.top = Color(r.pick(Appearance.SHIRTS)); a.lower = Color(r.pick(Appearance.PANTS))
	a.accent = Color(0.9, 0.88, 0.8)
	return a

static func _shader(name: String) -> Shader:
	if not _mats.has(name): _mats[name] = load("res://shaders/%s.gdshader" % name)
	return _mats[name]

static var _tex := {}
static func htex(file: String) -> Texture2D:
	if file == "": return null
	if not _tex.has(file): _tex[file] = load("res://assets/humans/tex/" + file)
	return _tex[file]

static func _lin_lum(c: Array) -> float:
	return maxf(0.004, float(c[0]) * 0.3 + float(c[1]) * 0.55 + float(c[2]) * 0.15)

func _shade(r: Rng) -> void:
	var noise: Texture2D = Mats.tex("noise")
	var T: Dictionary = spec.get("tex", {})
	for mi in skeleton.get_children():
		if not (mi is MeshInstance3D): continue
		var m := ShaderMaterial.new()
		match String(mi.name):
			"body":
				m.shader = _shader("skin")
				m.set_shader_parameter("tone", app.skin)  # source_color uniform: Godot linearises
				m.set_shader_parameter("age", float(spec.macro.age))
				m.set_shader_parameter("male", 1.0 if spec.sex == "m" else 0.0)
				m.set_shader_parameter("sweat", r.range_f(0.2, 0.7))
				m.set_shader_parameter("masks", load("res://assets/humans/skin_masks.png"))
				m.set_shader_parameter("noise", noise)
				if T.has("body"):
					m.set_shader_parameter("use_tex", true)
					m.set_shader_parameter("tex", htex(T.body.file))
					var mn: Array = T.body.mean
					m.set_shader_parameter("tex_mean", Vector3(mn[0], mn[1], mn[2]))
			"hair", "hair_extra", "brows", "moustache":
				m.shader = _shader("hair")
				m.set_shader_parameter("color", app.hair)
				m.set_shader_parameter("oil", r.range_f(0.3, 0.9))
				m.set_shader_parameter("noise", noise)
				if T.has(String(mi.name)) and mi.name in ["hair", "brows"]:
					var tt: Dictionary = T[String(mi.name)]
					m.set_shader_parameter("use_tex", true)
					m.set_shader_parameter("tex", htex(tt.file))
					m.set_shader_parameter("tex_lum", _lin_lum(tt.mean))
					m.set_shader_parameter("alpha_cut", 0.45 if mi.name == "hair" else 0.3)
			"eyes":
				m.shader = _shader("eye")
			"top", "lower", "drape", "extra", "shoes":
				m.shader = _shader("cloth")
				m.set_shader_parameter("weave", Mats.tex("cloth_n"))
				var col: Color; var col2 := app.border; var pat := 0
				match String(mi.name):
					"top": col = app.top; pat = app.top_pattern; col2 = app.top.darkened(0.4) if pat != 4 else Color(r.pick(Appearance.SAREE_BORDER))
					"lower": col = app.lower; pat = app.pattern
					"drape": col = app.drape; pat = 4 if spec.dress == "saree" else 0; col2 = app.border
					"extra": col = Color(0.9, 0.88, 0.8) if r.next() < 0.6 else Color(r.pick(["#c62828", "#1565c0", "#f9a825"])); pat = 1; col2 = col.darkened(0.3)
				m.set_shader_parameter("color", col)
				m.set_shader_parameter("color2", col2)
				m.set_shader_parameter("pattern", pat)
				m.set_shader_parameter("sheen", 0.5 if spec.dress == "saree" and mi.name in ["lower", "drape"] else 0.0)
			"lashes" when T.has("lashes"):
				m.shader = _shader("hair")
				m.set_shader_parameter("color", Color(0.01, 0.008, 0.006))
				m.set_shader_parameter("use_tex", true)
				m.set_shader_parameter("tex", htex(T.lashes.file))
				m.set_shader_parameter("tex_lum", 1.0)
				m.set_shader_parameter("alpha_cut", 0.3)
			"teeth":
				var sm := StandardMaterial3D.new(); sm.albedo_color = Color(0.85, 0.82, 0.74); sm.roughness = 0.3
				mi.material_override = sm
				continue
			"lashes":
				var sm := StandardMaterial3D.new(); sm.albedo_color = Color(0.02, 0.015, 0.01); sm.roughness = 0.8
				mi.material_override = sm
				continue
			_:
				continue
		mi.material_override = m

func reshade(a: Appearance, seed: int) -> void:
	app = a
	_shade(Rng.new(seed))

func _play(clip: String, blend := 0.25) -> void:
	if clip == current: return
	current = clip
	player.play(clip, blend)

## call each frame with ground speed (m/s); picks and speed-matches the locomotion clip
func animate(_dt: float, spd: float) -> void:
	speed = spd
	if action != "" and spd < 0.3:
		_play(action)
		player.speed_scale = 1.0
		return
	if spd < 0.25:
		_play(idle_clip); player.speed_scale = 1.0
	elif spd < 1.15:
		_play("walk_slow"); player.speed_scale = clampf(spd / CLIP_SPEED.walk_slow, 0.5, 1.4)
	elif spd < 2.2:
		_play("walk"); player.speed_scale = clampf(spd / CLIP_SPEED.walk, 0.7, 1.5)
	elif spd < 3.9:
		_play("jog"); player.speed_scale = clampf(spd / CLIP_SPEED.jog, 0.75, 1.3)
	else:
		_play("run"); player.speed_scale = clampf(spd / CLIP_SPEED.run, 0.8, 1.4)
