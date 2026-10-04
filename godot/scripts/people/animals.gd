class_name Animals
extends Node3D
## Street animals around the player: pariah dogs (asleep on footpaths through the heat of the day,
## trotting about at dusk and night), zebu cows standing or lying in quieter streets — sometimes in
## the carriageway, where traffic slows and swerves round them — and a few goats. All drawn with
## MultiMeshes and animated in `animal.gdshader` (no skeletons), so they cost almost nothing.

const SPAWN_R := 140.0
const DESPAWN_R := 175.0
const SPECIES := {
	"dog": {"coats": ["#c08850", "#c08850", "#d4a46c", "#8a5530", "#1c1814", "#e4cfa6", "#a8602e", "#6e6258"], "patch": "#f0e8da", "patchy": 0.55,
		"speed": 1.1, "gait": 1.4, "ranks": [1, 2, 3, 2, 1, 0.5], "per_100m": 1.6},
	"cow": {"coats": ["#e8e4dc", "#e0dcd2", "#b8b4ac", "#a09c94", "#8a6040", "#f0ece4"], "patch": "#3a3632", "patchy": 0.12,
		"speed": 0.55, "gait": 0.6, "ranks": [0.6, 1, 0.8, 0.3, 0.1, 0.0], "per_100m": 0.45},
	"goat": {"coats": ["#1c1814", "#2a221c", "#6a4228", "#e8e2d8", "#8a6a4a"], "patch": "#f2eee6", "patchy": 0.45,
		"speed": 0.8, "gait": 1.3, "ranks": [1, 0.6, 0.2, 0.0, 0.0, 0.0], "per_100m": 0.25},
}

var pack: CityPack
var focus := Vector3.ZERO
var rng := Rng.new(2718)
var agents: Array = []
var mms := {}
var meta := {}
var stats := {"dogs": 0, "cows": 0, "goats": 0}
var obstacles: Array[Vector3] = []   # animals standing in a carriageway (fed to traffic)

func setup(p: CityPack) -> void:
	pack = p
	var m = CityPack.load_json("res://assets/animals/animals.json")
	meta = m if m else {}
	for sp in SPECIES:
		var scene: PackedScene = load("res://assets/animals/%s.glb" % sp)
		if scene == null: continue
		var n := scene.instantiate()
		var mi: MeshInstance3D = n if n is MeshInstance3D else n.find_children("*", "MeshInstance3D", true, false)[0]
		var mesh: Mesh = mi.mesh
		n.free()
		var mat := ShaderMaterial.new()
		mat.shader = load("res://shaders/animal.gdshader")
		var md: Dictionary = meta.get(sp, {})
		var hips: Array = md.get("hips", [])
		for i in mini(4, hips.size()):
			mat.set_shader_parameter("hip%d" % i, Vector3(hips[i][0], hips[i][1], hips[i][2]))
		mat.set_shader_parameter("lie_drop", float(md.get("lie_drop", 0.3)))
		mat.set_shader_parameter("height", float(md.get("height", 0.5)))
		mat.set_shader_parameter("patch_col", Color(SPECIES[sp].patch))
		mat.set_shader_parameter("patchy", float(SPECIES[sp].patchy))
		mat.set_shader_parameter("lie_front", 1.45 if sp == "dog" else -1.5)
		mat.set_shader_parameter("side_r", {"dog": 0.12, "cow": 0.32, "goat": 0.13}[sp])
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = mesh
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = mat
		mmi.custom_aabb = AABB(Vector3(-5000, -50, -5000), Vector3(10000, 100, 10000))
		add_child(mmi)
		mms[sp] = mmi

## dogs sleep through the hot middle of the day and are up at dusk and at night
func _active(sp: String, hour: float) -> float:
	var h := fposmod(hour, 24.0)
	if sp == "dog": return 0.15 + 0.55 * (smoothstep(16.5, 19.0, h) + 1.0 - smoothstep(5.0, 8.0, h)) * 0.5 + 0.2 * (1.0 - smoothstep(9.0, 11.0, h)) * smoothstep(5.0, 7.0, h)
	return 0.25

func update(dt: float, hour: float) -> void:
	if pack == null or mms.is_empty(): return
	var keep: Array = []
	for a in agents:
		if Vector2(a.p.x - focus.x, a.p.z - focus.z).length() < DESPAWN_R: keep.append(a)
	agents = keep
	var counts := {}
	for a in agents: counts[a.sp] = counts.get(a.sp, 0) + 1
	for sp in SPECIES:
		var want := int(SPECIES[sp].per_100m * 9.0 * (SPAWN_R / 100.0) * (1.0 if sp != "dog" else 1.0))
		var tries := 0
		while counts.get(sp, 0) < want and tries < 8:
			tries += 1
			if _spawn(sp, hour): counts[sp] = counts.get(sp, 0) + 1
	obstacles.clear()
	for a in agents:
		_step(a, dt, hour)
		if a.in_road and a.sp == "cow": obstacles.append(a.p)
	_render()
	stats = {"dogs": counts.get("dog", 0), "cows": counts.get("cow", 0), "goats": counts.get("goat", 0)}

func populate(hour: float) -> void:
	agents.clear()
	for k in 30: update(0.5, hour)

func _spawn(sp: String, hour: float) -> bool:
	var ang := rng.next() * TAU
	var dist := sqrt(rng.next()) * SPAWN_R
	var x := focus.x + cos(ang) * dist
	var z := focus.z + sin(ang) * dist
	var rr := pack.nearest_road(x, z, 30.0, 1)
	if rr.is_empty(): return false
	var road: Dictionary = pack.region.roads[rr.ri]
	var rank := clampi(int(road.rank), 0, 5)
	if rng.next() > float(SPECIES[sp].ranks[rank]): return false
	var w: float = road.w
	var side := 1.0 if rng.next() < 0.5 else -1.0
	var in_road := sp == "cow" and rng.next() < 0.3
	var lat: float = side * (rng.range_f(0.5, w * 0.45) if in_road else w * 0.5 + rng.range_f(0.4, 2.4))
	var dir: Vector2 = rr.dir
	var nn := Vector2(-dir.y, dir.x)
	var p2: Vector2 = rr.p + nn * lat
	var act := _active(sp, hour)
	var st: int = 1 if rng.next() < act * 0.6 else ([2, 4, 3, 0][rng.pick_w([3.0, 4.0, 1.5, 1.5])] if sp == "dog" else [0, 2, 0][rng.pick_w([3.0, 2.0, 1.0])])
	var cols: Array = SPECIES[sp].coats
	agents.append({"sp": sp, "p": Vector3(p2.x, RegionBuilder.ROAD_Y if in_road else 0.0, p2.y), "yaw": rng.next() * TAU, "state": st,
		"timer": rng.range_f(8.0, 60.0), "dir": dir * (1.0 if rng.next() < 0.5 else -1.0), "ri": rr.ri, "seed": rng.next(),
		"col": Color(cols[int(rng.next() * cols.size()) % cols.size()]).srgb_to_linear() * rng.range_f(0.85, 1.1), "in_road": in_road,
		"phase": rng.next() * 50.0, "lat": lat})
	return true

func _step(a: Dictionary, dt: float, hour: float) -> void:
	a.timer -= dt
	if a.timer <= 0.0:
		var act := _active(a.sp, hour)
		if a.state == 1:
			a.state = [0, 2, 3, 4][rng.pick_w([2.0, 3.0, 1.0, 2.0])] if a.sp == "dog" else [0, 2][rng.pick_w([2.0, 1.0])]
		elif rng.next() < act:
			a.state = 1
			if rng.next() < 0.5: a.dir = -a.dir
		else:
			a.state = [0, 2, 3, 4][rng.pick_w([1.0, 3.0, 1.0, 3.0])] if a.sp == "dog" else [0, 2][rng.pick_w([2.0, 1.0])]
		a.timer = rng.range_f(6.0, 45.0) if a.state != 1 else rng.range_f(4.0, 20.0)
	if a.state == 1:
		# amble along the road edge; follow the road direction where it bends
		var rr := pack.nearest_road(a.p.x, a.p.z, 25.0, 0)
		if not rr.is_empty():
			var d: Vector2 = rr.dir
			if d.dot(a.dir) < 0.0: d = -d
			a.dir = (a.dir as Vector2).lerp(d, clampf(dt * 2.0, 0.0, 1.0)).normalized()
			# drift back to the intended offset from the centreline
			var nn := Vector2(-rr.dir.y, rr.dir.x)
			var cur: float = (Vector2(a.p.x, a.p.z) - rr.p).dot(nn)
			var corr: float = clampf(float(a.lat) - cur, -0.6, 0.6)
			var step: Vector2 = a.dir * float(SPECIES[a.sp].speed) * dt + nn * corr * dt * 0.5
			a.p = Vector3(a.p.x + step.x, a.p.y, a.p.z + step.y)
		var dd: Vector2 = a.dir
		a.yaw = lerp_angle(a.yaw, atan2(-dd.x, -dd.y), clampf(dt * 3.0, 0.0, 1.0))

func _render() -> void:
	var bufs := {}
	for sp in mms: bufs[sp] = PackedFloat32Array()
	for a in agents:
		if not bufs.has(a.sp): continue
		var b := Basis(Vector3.UP, a.yaw)
		var p: Vector3 = a.p
		var c: Color = a.col
		var gait: float = SPECIES[a.sp].gait if a.state == 1 else 0.0
		bufs[a.sp].append_array([b.x.x, b.y.x, b.z.x, p.x, b.x.y, b.y.y, b.z.y, p.y, b.x.z, b.y.z, b.z.z, p.z, c.r, c.g, c.b, 1.0, float(a.state), a.phase, gait, a.seed])
	for sp in mms:
		var mm: MultiMesh = mms[sp].multimesh
		var buf: PackedFloat32Array = bufs[sp]
		var cnt := buf.size() / 20
		if mm.instance_count != cnt: mm.instance_count = cnt
		if cnt > 0: mm.buffer = buf
