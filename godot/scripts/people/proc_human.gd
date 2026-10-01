class_name ProcHuman
extends Node3D
## Procedural articulated human (placeholder for the rigged MPFB humans, see docs/PLACEHOLDERS.md).
## Segmented body on pivot nodes (hips, spine, head, shoulders/elbows, hips/knees) with clothing
## variants from Appearance, and a procedural gait: walk/run cycles, idle sway, the head wobble.

var app: Appearance
var parts := {}
var phase := 0.0
var speed := 0.0          # m/s, drives the gait
var _mat: StandardMaterial3D

const SEG := 10

func build(a: Appearance) -> void:
	app = a
	_mat = StandardMaterial3D.new()
	_mat.vertex_color_use_as_albedo = true
	_mat.roughness = 0.85
	var s := a.scale * (1.0 if a.sex == "m" else 0.94)
	var skin := a.skin.srgb_to_linear()
	var top := a.top.srgb_to_linear()
	var lower := a.lower.srgb_to_linear()
	var skirt := a.variant in ["man_veshti", "man_lungi", "woman_saree"]
	var hip_y := 0.94 * s
	var hips := _pivot("hips", self, Vector3(0, hip_y, 0))
	var spine := _pivot("spine", hips, Vector3(0, 0.05 * s, 0))
	# torso: tapered from waist to chest, slightly flattened
	var torso := MB.new(false)
	var w_waist := (0.15 if a.sex == "m" else 0.14) * s
	var w_chest := (0.19 if a.sex == "m" else 0.165) * s
	_lathe(torso, [[0.0, w_waist], [0.18 * s, w_waist * 1.02], [0.36 * s, w_chest], [0.46 * s, w_chest * 0.92], [0.52 * s, 0.07 * s]], top, Vector3(1, 1, 0.68))
	if a.towel:  # towel over the shoulder
		torso.box(Vector3(0.1 * s, 0.4 * s, 0), Vector3(0.05 * s, 0.13 * s, 0.11 * s), 0.0, Color(0.9, 0.88, 0.8).srgb_to_linear(), Vector4.ZERO)
	if a.variant == "woman_saree":  # pallu: diagonal drape over the left shoulder
		torso.beam(Vector3(0.16 * s, 0.48 * s, 0.03 * s), Vector3(-0.14 * s, 0.02 * s, 0.1 * s), 0.18 * s, 0.03 * s, a.drape.srgb_to_linear(), Vector4.ZERO)
		torso.beam(Vector3(0.16 * s, 0.48 * s, -0.03 * s), Vector3(0.12 * s, -0.2 * s, -0.14 * s), 0.22 * s, 0.03 * s, a.drape.srgb_to_linear() * 0.9, Vector4.ZERO)
	if a.variant == "woman_churidar":  # dupatta across the chest
		torso.beam(Vector3(-0.17 * s, 0.46 * s, 0.05 * s), Vector3(0.17 * s, 0.46 * s, 0.05 * s), 0.08 * s, 0.03 * s, a.drape.srgb_to_linear(), Vector4.ZERO)
	_part(spine, "torso", torso)
	# neck + head
	var neck := _pivot("neck", spine, Vector3(0, 0.5 * s, 0))
	var head := MB.new(false)
	_lathe(head, [[0.0, 0.045 * s], [0.07 * s, 0.05 * s], [0.1 * s, 0.085 * s], [0.17 * s, 0.098 * s], [0.25 * s, 0.09 * s], [0.3 * s, 0.05 * s], [0.315 * s, 0.0]], skin, Vector3(0.92, 1, 1.05))
	head.box(Vector3(0, 0.17 * s, -0.1 * s), Vector3(0.012 * s, 0.03 * s, 0.018 * s), 0.0, skin * 0.95, Vector4.ZERO)  # nose
	var hair := a.hair.srgb_to_linear()
	_lathe(head, [[0.17 * s, 0.103 * s], [0.25 * s, 0.096 * s], [0.3 * s, 0.06 * s], [0.322 * s, 0.0]], hair, Vector3(0.95, 1, 1.08))
	if a.sex == "f" and a.variant != "child":  # bun / plait
		head.cylinder(0, 0.11 * s, 0.11 * s, 0.045 * s, 0.07 * s, 8, hair, Vector4.ZERO)
		if a.jasmine: head.cylinder(0, 0.1 * s, 0.13 * s, 0.05 * s, 0.03 * s, 8, Color(0.92, 0.9, 0.82), Vector4.ZERO)
	if a.mustache:
		head.box(Vector3(0, 0.125 * s, -0.098 * s), Vector3(0.03 * s, 0.006 * s, 0.006 * s), 0.0, hair, Vector4.ZERO)
	_part(neck, "head", head)
	parts.neck = neck
	# arms
	for side in [-1.0, 1.0]:
		var nm := "l" if side < 0 else "r"
		var sh := _pivot("sh_" + nm, spine, Vector3(side * (w_chest + 0.02 * s), 0.44 * s, 0))
		var up := MB.new(false)
		var sleeve := a.variant != "woman_saree" or true
		var sleeve_len := 0.12 if a.variant == "woman_saree" else (0.16 if a.top_pattern != 3 else 0.28)
		_lathe(up, [[0.0, 0.05 * s], [-sleeve_len * s, 0.048 * s]], top if sleeve else skin, Vector3.ONE, true)
		_lathe(up, [[-sleeve_len * s, 0.04 * s], [-0.29 * s, 0.035 * s]], skin, Vector3.ONE, true)
		_part(sh, "upper", up)
		var el := _pivot("el_" + nm, sh, Vector3(0, -0.29 * s, 0))
		var fo := MB.new(false)
		_lathe(fo, [[0.0, 0.034 * s], [-0.24 * s, 0.026 * s], [-0.3 * s, 0.03 * s], [-0.36 * s, 0.015 * s]], skin, Vector3(1, 1, 0.7), true)
		_part(el, "fore", fo)
		parts["sh_" + nm] = sh; parts["el_" + nm] = el
	# legs
	for side in [-1.0, 1.0]:
		var nm := "l" if side < 0 else "r"
		var th := _pivot("th_" + nm, hips, Vector3(side * 0.085 * s, 0, 0))
		var thm := MB.new(false)
		_lathe(thm, [[0.0, 0.075 * s], [-0.44 * s, 0.05 * s]], lower if a.variant in ["man_pants", "woman_churidar", "child"] else skin, Vector3.ONE, true)
		_part(th, "thigh", thm)
		var kn := _pivot("kn_" + nm, th, Vector3(0, -0.44 * s, 0))
		var sm := MB.new(false)
		var shin_col := lower if a.variant in ["man_pants", "woman_churidar"] else skin
		_lathe(sm, [[0.0, 0.048 * s], [-0.2 * s, 0.045 * s], [-0.42 * s, 0.032 * s]], shin_col, Vector3.ONE, true)
		sm.box(Vector3(0, -0.47 * s, -0.04 * s), Vector3(0.045 * s, 0.025 * s, 0.12 * s), 0.0, Color(0.12, 0.08, 0.05), Vector4.ZERO)  # chappal
		_part(kn, "shin", sm)
		parts["th_" + nm] = th; parts["kn_" + nm] = kn
	# wrapped garments: veshti / lungi / saree as a skirt from the waist (sways with the gait)
	if skirt:
		var sk := MB.new(false)
		var hem := 0.06 * s if a.variant != "man_lungi" or true else 0.3 * s
		var top_y := 0.08 * s
		var bot_y := -hip_y + hem
		_lathe(sk, [[top_y, w_waist * 1.05], [-0.2 * s, w_waist * 1.35], [bot_y + 0.12 * s, w_waist * 1.45], [bot_y, w_waist * 1.42]], lower, Vector3(1, 1, 0.85))
		if a.pattern == 2:  # border band at the hem
			_lathe(sk, [[bot_y + 0.1 * s, w_waist * 1.455], [bot_y - 0.002, w_waist * 1.43]], a.border.srgb_to_linear(), Vector3(1.002, 1, 0.852))
		var skp := _pivot("skirt", hips, Vector3.ZERO)
		_part(skp, "skirt", sk)
		parts.skirt = skp
	else:
		var pl := MB.new(false)
		_lathe(pl, [[0.1 * s, w_waist * 1.02], [-0.12 * s, w_waist * 1.12]], lower, Vector3(1, 1, 0.8))
		_part(hips, "pelvis", pl)
	parts.hips = hips; parts.spine = spine

func _pivot(nm: String, parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.name = nm
	n.position = pos
	parent.add_child(n)
	return n

func _part(parent: Node3D, nm: String, mb: MB) -> void:
	var mi := MeshInstance3D.new()
	mi.name = nm
	mi.mesh = mb.to_mesh(_mat)
	parent.add_child(mi)

## surface of revolution around Y from a profile [[y, radius], …]; `sc` scales x/z (flattening)
func _lathe(mb: MB, prof: Array, col: Color, sc := Vector3.ONE, cap_ends := false) -> void:
	var base := mb.count()
	for i in prof.size():
		var y: float = prof[i][0]; var rr: float = prof[i][1]
		for j in SEG + 1:
			var a := float(j) / SEG * TAU
			var d := Vector3(sin(a) * sc.x, 0, cos(a) * sc.z)
			mb.vert(Vector3(d.x * rr, y, d.z * rr), d.normalized(), col, Vector2(float(j) / SEG, y), Vector4.ZERO)
	for i in prof.size() - 1:
		for j in SEG:
			var a := base + i * (SEG + 1) + j
			var b := a + SEG + 1
			mb.idx.append_array([a, b, a + 1, a + 1, b, b + 1])
	mb._fix_last_tris(base, (prof.size() - 1) * SEG * 6)
	if cap_ends:
		var last: Array = prof[prof.size() - 1]
		mb.cylinder(0, last[0] - 0.001, 0, last[1], 0.001, SEG, col, Vector4.ZERO)

## advance the procedural animation; `spd` in m/s
func animate(dt: float, spd: float) -> void:
	speed = lerpf(speed, spd, clampf(dt * 8.0, 0.0, 1.0))
	var s := app.scale if app else 1.0
	var run := clampf((speed - 2.5) / 3.0, 0.0, 1.0)
	var freq := (1.7 + speed * 0.55) * (app.gait if app else 1.0)
	if speed > 0.15: phase += dt * freq * TAU * 0.5
	else: phase = lerpf(phase, roundf(phase / PI) * PI, clampf(dt * 4.0, 0.0, 1.0))
	var amp := clampf(speed / 1.4, 0.0, 1.0) * lerpf(0.42, 0.75, run)
	var sw := sin(phase)
	for side in [-1.0, 1.0]:
		var nm := "l" if side < 0 else "r"
		var leg: float = sw * side * amp
		parts["th_" + nm].rotation.x = leg
		parts["kn_" + nm].rotation.x = -(maxf(0.0, -cos(phase + (0.0 if side > 0 else PI)) * amp * 1.3) + run * 0.3)
		parts["sh_" + nm].rotation.x = -leg * 0.8
		parts["sh_" + nm].rotation.z = side * 0.06
		parts["el_" + nm].rotation.x = 0.15 + run * 1.1
	parts.hips.position.y = 0.94 * s * (1.0 if app.sex == "m" else 0.94) + absf(cos(phase)) * 0.03 * amp
	parts.spine.rotation.x = -run * 0.18
	parts.spine.rotation.y = sw * 0.08 * amp
	if parts.has("skirt"): parts.skirt.rotation.x = sw * 0.06 * amp
	# idle: gentle breathing and the occasional head wobble
	var t := Time.get_ticks_msec() * 0.001
	parts.neck.rotation.z = sin(t * 5.0) * 0.07 * (1.0 - amp) * maxf(0.0, sin(t * 0.7 + float(get_instance_id() % 17)))
