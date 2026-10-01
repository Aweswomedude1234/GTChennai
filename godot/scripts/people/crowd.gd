class_name Crowd
extends Node3D
## Pedestrian simulation and rendering (BRIEF §7). Agents walk the edges of the OSM road graph
## (footpaths where they exist, the carriageway edge where they don't — as in Chennai), choose new
## roads at junctions, pause to chat or drink tea, and stand in groups at shops. Density follows the
## time of day and the npc_density setting.
## Tiers: near (< NEAR_R) agents get a full skeletal HumanActor (pooled); everyone else is drawn by
## one VAT MultiMesh per body variant (vertex-animation textures from tools/humans/bake_vat.py).

const NEAR_R := 28.0
const MAX_NEAR := 36
const SPAWN_R := 170.0
const DESPAWN_R := 200.0

var pack: CityPack
var focus := Vector3.ZERO
var specs: Array = []
var clips := {}
var rng := Rng.new(99)
var agents: Array = []         # Dictionary per agent
var mms: Array = []            # MultiMeshInstance3D per variant
var actor_pool: Array = []     # [HumanActor, spec index]
var target := 0
var enabled := true
var stats := {"agents": 0, "near": 0}
var _road_cache := {}

func setup(p: CityPack) -> void:
	pack = p
	specs = HumanActor.specs()
	var cj = CityPack.load_json("res://assets/humans/vat/clips.json")
	clips = cj.clips if cj else {}
	var cloth := Mats.tex("cloth_n")
	for i in specs.size():
		var id: String = specs[i].id
		var mesh_scene: PackedScene = load("res://assets/humans/vat/%s.glb" % id)
		var mesh: Mesh = null
		if mesh_scene:
			var n := mesh_scene.instantiate()
			var mi: MeshInstance3D = n.find_child("*", true, false) if not (n is MeshInstance3D) else n
			for c in n.get_children(): if c is MeshInstance3D: mi = c
			if mi: mesh = mi.mesh
			n.free()
		var mat := ShaderMaterial.new()
		mat.shader = load("res://shaders/crowd.gdshader")
		mat.set_shader_parameter("vat_pos", load("res://assets/humans/vat/%s_pos.png" % id))
		mat.set_shader_parameter("vat_nrm", load("res://assets/humans/vat/%s_nrm.png" % id))
		mat.set_shader_parameter("weave", cloth)
		mat.set_shader_parameter("grey_hair", 1.0 if float(specs[i].macro.age) > 0.8 else 0.0)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = mesh
		mm.instance_count = 0
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		mmi.custom_aabb = AABB(Vector3(-5000, -50, -5000), Vector3(10000, 100, 10000))
		add_child(mmi)
		mms.append(mmi)

## people per hectare-ish along roads by time of day (evening peak, near-empty small hours)
func _density(hour: float) -> float:
	var h := hour
	var d := 0.25
	if h < 5.0: d = 0.06
	elif h < 7.0: d = lerpf(0.1, 0.55, (h - 5.0) / 2.0)
	elif h < 10.0: d = 0.8
	elif h < 16.0: d = 0.6
	elif h < 21.0: d = 1.0
	elif h < 23.0: d = lerpf(0.8, 0.2, (h - 21.0) / 2.0)
	else: d = 0.12
	return d * float(Settings.get_v("npc_density", 1.0))

func update(dt: float, hour: float) -> void:
	if not enabled or specs.is_empty(): return
	target = int(1500.0 * _density(hour))
	# despawn far agents, spawn new ones along nearby roads
	var keep: Array = []
	for a in agents:
		if Vector2(a.p.x - focus.x, a.p.z - focus.z).length() < DESPAWN_R: keep.append(a)
		elif a.actor: _release(a)
	agents = keep
	var spawn_budget := 40
	while agents.size() < target and spawn_budget > 0:
		spawn_budget -= 1
		var a := _spawn()
		if a.is_empty(): break
		agents.append(a)
	for a in agents: _step(a, dt)
	_render()

func _spawn() -> Dictionary:
	# random point in the ring; snap to the nearest road edge
	for tries in 6:
		var ang := rng.next() * TAU
		var dist := sqrt(rng.next()) * SPAWN_R
		var x := focus.x + cos(ang) * dist
		var z := focus.z + sin(ang) * dist
		var rr := pack.nearest_road(x, z, 30.0, 1)
		if rr.is_empty(): continue
		var road: Dictionary = pack.region.roads[rr.ri]
		var rank := int(road.rank)
		# busier streets get more people: reject some spawns on quiet lanes
		if rng.next() > [0.0, 0.35, 0.55, 0.8, 1.0, 1.0, 1.0][rank]: continue
		var si := int(rng.next() * specs.size()) % specs.size()
		var spec: Dictionary = specs[si]
		var a := {"ri": rr.ri, "seg": rr.seg, "dir": 1 if rng.next() < 0.5 else -1, "side": 1.0 if rng.next() < 0.5 else -1.0,
			"p": Vector3(), "h": 0.0, "v": 0.0, "si": si, "state": "walk", "timer": rng.range_f(5.0, 40.0),
			"speed": rng.range_f(0.95, 1.45) * (0.75 if float(spec.macro.age) > 0.8 else 1.0) * (0.85 if String(spec.id).begins_with("child") else 1.0),
			"phase": rng.next() * 60.0, "actor": null, "seed": rng.seed_int(), "lane": rng.range_f(0.2, 1.0)}
		var app := HumanActor.appearance_for(spec, Rng.new(a.seed))
		a.top = app.top; a.lower = app.lower if spec.dress != "saree" else app.lower
		a.skin = _skin_index(app.skin)
		a.app = app
		var P: Array = road.pts
		var t := rng.next()
		var i: int = rr.seg
		var pa := Vector2(P[i * 2], P[i * 2 + 1]); var pb := Vector2(P[i * 2 + 2], P[i * 2 + 3])
		a.t = t
		a.p = _edge_point(a, pa, pb, t)
		return a
	return {}

static func _skin_index(c: Color) -> int:
	var best := 0; var bd := 9.0
	for i in Appearance.SKIN.size():
		var d := Color(Appearance.SKIN[i])
		var dd := absf(d.r - c.r) + absf(d.g - c.g) + absf(d.b - c.b)
		if dd < bd: bd = dd; best = i
	return best

func _road_edge(ri: int) -> float:
	if _road_cache.has(ri): return _road_cache[ri]
	var r: Dictionary = pack.region.roads[ri]
	var rank := int(r.rank)
	var hw := float(r.w) * 0.5
	# footpath centre on main roads; otherwise the edge of the carriageway (people walk on the road)
	var off := hw + (1.0 if rank >= 3 else -0.7)
	_road_cache[ri] = off
	return off

func _edge_point(a: Dictionary, pa: Vector2, pb: Vector2, t: float) -> Vector3:
	var d := (pb - pa).normalized()
	var nn: Vector2 = Vector2(-d.y, d.x) * float(a.side)
	var off: float = _road_edge(a.ri) + (float(a.lane) - 0.5) * 0.8
	var p := pa.lerp(pb, t) + nn * off
	return Vector3(p.x, 0.0 if _road_edge(a.ri) < float(pack.region.roads[a.ri].w) * 0.5 else 0.17, p.y)

func _step(a: Dictionary, dt: float) -> void:
	a.timer -= dt
	if a.state != "walk":
		a.v = 0.0
		if a.timer <= 0.0:
			a.state = "walk"; a.timer = rng.range_f(10.0, 50.0)
		return
	if a.timer <= 0.0:
		# pause: chat, a glass of tea, or just stand and look around
		a.state = ["idle", "talk", "drink_tea"][rng.pick_w([4, 3, 2])]
		a.timer = rng.range_f(4.0, 18.0)
		return
	var road: Dictionary = pack.region.roads[a.ri]
	var P: Array = road.pts
	var n := P.size() / 2
	var i: int = a.seg
	var pa := Vector2(P[i * 2], P[i * 2 + 1]); var pb := Vector2(P[i * 2 + 2], P[i * 2 + 3])
	var L := maxf(pa.distance_to(pb), 0.01)
	a.t += dt * a.speed / L * a.dir
	if a.t > 1.0 or a.t < 0.0:
		var ni: int = i + a.dir
		if ni < 0 or ni >= n - 1:
			_next_road(a)
		else:
			a.seg = ni
			a.t = 0.0 if a.dir > 0 else 1.0
		road = pack.region.roads[a.ri]
		P = road.pts
		i = a.seg
		pa = Vector2(P[i * 2], P[i * 2 + 1]); pb = Vector2(P[i * 2 + 2], P[i * 2 + 3])
	var np := _edge_point(a, pa, pb, clampf(a.t, 0.0, 1.0))
	var mv: Vector3 = np - (a.p as Vector3)
	if mv.length() > 0.001: a.h = atan2(-mv.x, -mv.z)
	a.v = minf(mv.length() / maxf(dt, 0.001), 3.0)
	a.p = np

func _next_road(a: Dictionary) -> void:
	var r: Dictionary = pack.region.roads[a.ri]
	var n: int = r.pts.size() / 2
	var j: int = r.j[n - 1] if a.dir > 0 else r.j[0]
	var cands: Array = []
	if j >= 0:
		for ri in pack.region.junctions[j].roads:
			if ri != a.ri and int(pack.region.roads[ri].rank) >= 1: cands.append(ri)
	if cands.is_empty():
		a.dir = -a.dir
		a.t = clampf(a.t, 0.0, 1.0)
		return
	var ri: int = rng.pick(cands)
	var rd: Dictionary = pack.region.roads[ri]
	var m: int = rd.pts.size() / 2
	a.ri = ri
	if rd.j[0] == j: a.dir = 1; a.seg = 0; a.t = 0.0
	else: a.dir = -1; a.seg = m - 2; a.t = 1.0
	if rng.next() < 0.25: a.side = -a.side   # crosses the road at the junction

func _clip(a: Dictionary) -> String:
	if a.state != "walk": return a.state
	return "walk" if a.speed > 1.15 else "walk_slow"

func _render() -> void:
	# near tier: pooled skeletal actors for the closest agents
	var near_list: Array = []
	for a in agents:
		var d: float = Vector2(a.p.x - focus.x, a.p.z - focus.z).length()
		a.d = d
		if d < NEAR_R: near_list.append(a)
	near_list.sort_custom(func(x, y): return x.d < y.d)
	var near_set := {}
	for k in mini(near_list.size(), MAX_NEAR): near_set[near_list[k]] = true
	for a in agents:
		if near_set.has(a):
			if a.actor == null: _acquire(a)
			var act: HumanActor = a.actor
			act.global_position = a.p
			act.rotation.y = a.h
			act.action = a.state if a.state != "walk" else ""
			act.animate(0.016, a.v if a.state == "walk" else 0.0)
		elif a.actor:
			_release(a)
	stats.agents = agents.size(); stats.near = near_set.size()
	# mid/far tier: rebuild every variant's multimesh buffer in one go
	var per: Array = []
	for i in mms.size(): per.append(PackedFloat32Array())
	for a in agents:
		if a.actor: continue
		var c: Dictionary = clips.get(_clip(a), clips.get("walk", {"row": 0, "frames": 1}))
		var b := Basis(Vector3.UP, float(a.h) + PI)   # VAT bodies face +Z like the glTF
		var buf: PackedFloat32Array = per[a.si]
		buf.append_array([b.x.x, b.y.x, b.z.x, a.p.x, b.x.y, b.y.y, b.z.y, a.p.y, b.x.z, b.y.z, b.z.z, a.p.z])
		var top: Color = a.top
		buf.append_array([top.r, top.g, top.b, a.skin / 8.0])
		var low: Color = a.lower
		var packed := float(int(low.r8) * 65536 + int(low.g8) * 256 + int(low.b8))
		var spd: float = a.v / 1.35 if a.state == "walk" else 1.0
		buf.append_array([float(int(c.row) * 1000 + int(c.frames)), a.phase, spd, packed])
		per[a.si] = buf
	for i in mms.size():
		var mm: MultiMesh = mms[i].multimesh
		var buf: PackedFloat32Array = per[i]
		var cnt := buf.size() / 20
		if mm.instance_count != cnt:
			mm.instance_count = cnt
		if cnt > 0: mm.buffer = buf

func _acquire(a: Dictionary) -> void:
	var act: HumanActor = null
	for k in actor_pool.size():
		if actor_pool[k][1] == a.si:
			act = actor_pool[k][0]; actor_pool.remove_at(k); break
	if act == null:
		act = HumanActor.new()
		add_child(act)
		act.build(specs[a.si], a.app, a.seed)
	else:
		act.reshade(a.app, a.seed)
	act.visible = true
	a.actor = act

func _release(a: Dictionary) -> void:
	var act: HumanActor = a.actor
	a.actor = null
	if act == null: return
	act.visible = false
	if actor_pool.size() < MAX_NEAR + 8: actor_pool.append([act, a.si])
	else: act.queue_free()
