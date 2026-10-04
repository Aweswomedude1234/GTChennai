class_name Traffic
extends Node3D
## Ambient traffic on the OSM road graph, Chennai style (BRIEF §5, STYLE_BIBLE §8): mostly
## two-wheelers, then autos and small hatchbacks, MNT buses on the main roads. Drives on the left,
## but lanes are a suggestion: two-wheelers and autos weave into any gap, filter past slower
## vehicles, and bunch up at junctions. Kinematic (cheap) agents: each follows a road polyline at a
## lateral offset with an IDM car-following model against whatever overlaps it laterally ahead;
## bodies are pooled VehicleModels on AnimatableBody3D colliders so the player can hit them.

const SPAWN_R := 240.0
const DESPAWN_R := 220.0
const MIN_SPAWN_D := 70.0           # don't pop vehicles in right next to the camera
## kind: length, width, cruise speed (m/s, on a big road), comfortable accel/decel, time headway, weave
const KINDS := {
	"bike": {"len": 2.0, "w": 0.8, "v": 13.0, "a": 2.4, "b": 3.5, "T": 0.8, "weave": 1.0, "min_rank": 1},
	"scooter": {"len": 1.8, "w": 0.75, "v": 11.0, "a": 2.0, "b": 3.0, "T": 0.9, "weave": 0.8, "min_rank": 1},
	"auto": {"len": 2.7, "w": 1.35, "v": 10.0, "a": 1.6, "b": 3.0, "T": 1.0, "weave": 0.6, "min_rank": 2},
	"hatch": {"len": 3.8, "w": 1.7, "v": 14.0, "a": 1.8, "b": 3.5, "T": 1.2, "weave": 0.15, "min_rank": 2},
	"bus": {"len": 12.0, "w": 2.6, "v": 11.0, "a": 0.9, "b": 2.5, "T": 1.5, "weave": 0.0, "min_rank": 3},
}
const MIX := {"bike": 34.0, "scooter": 22.0, "auto": 17.0, "hatch": 22.0, "bus": 5.0}
const NEAR_R := 65.0                 # full bodies (+ skeletal riders, colliders) inside this range
var MAX_NEAR := 40 if not Settings.has_arg("lowmem") else 5

var pack: CityPack
var focus := Vector3.ZERO
var obstacles: Array[Vector3] = []   # player / player's vehicle positions (agents brake and honk)
var rng := Rng.new(4711)
var agents: Array = []
var pools := {}                      # kind → Array of free bodies
var enabled := true
var density := 1.0
var stats := {"agents": 0, "spawned": 0, "near": 0}
var _len := {}                       # road index → PackedFloat32Array cumulative lengths
var _cand: Array = []                # [road index, weight] of roads near the focus
var _cand_w: Array = []
var _cand_at := Vector3(1e9, 0, 1e9)
var _t := 0.0
var sound: Soundscape                # horns (set by World)
var crowd: Crowd                     # far-tier riders are drawn by the crowd's VAT MultiMeshes
var _mm := {}                        # kind → MultiMeshInstance3D (far tier, baked low-detail bodies)
var _specs: Array = []
var _actor_pool := {}                # spec index → Array[HumanActor]

func setup(p: CityPack, c: Crowd = null) -> void:
	pack = p
	crowd = c
	_specs = HumanActor.specs()
	for k in KINDS:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = VehicleModel.baked(k, 0, true)
		mm.instance_count = 0
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.custom_aabb = AABB(Vector3(-5000, -50, -5000), Vector3(10000, 100, 10000))
		add_child(mmi)
		_mm[k] = mmi

## time-of-day factor: morning and evening peaks, near-empty small hours
func _hour_f(hour: float) -> float:
	var h := fposmod(hour, 24.0)
	var f := 0.12 + 0.55 * smoothstep(5.0, 8.5, h) * (1.0 - smoothstep(22.0, 24.0, h))
	f += 0.35 * exp(-pow((h - 9.3) / 1.4, 2.0)) + 0.4 * exp(-pow((h - 18.5) / 1.8, 2.0))
	return clampf(f, 0.0, 1.2)

## vehicles per 100 m of road (both directions) at peak, by road rank: arterials are jammed,
## residential lanes see the odd bike or auto
const PER_100M := [0.4, 1.5, 4.0, 10.0, 20.0, 26.0]
const MAX_AGENTS := 420
const DENSE_R := 170.0                # roads are filled to their quota within this radius

func update(dt: float, hour: float) -> void:
	if not enabled or pack == null: return
	_t += dt
	if focus.distance_to(_cand_at) > 30.0: _gather()
	var hf := _hour_f(hour) * density
	var tries := 0
	while agents.size() < MAX_AGENTS and tries < 10:
		tries += 1
		if not _spawn(false, hf): break
	_step_all(dt)
	stats.agents = agents.size()

## fill up immediately (harness / game start): spawns anywhere in range, including close by
func populate(hour: float) -> void:
	_gather()
	var hf := _hour_f(hour) * density
	for k in 3000:
		if agents.size() >= MAX_AGENTS or not _spawn(true, hf): break

## candidate roads near the focus with how much of each lies inside DENSE_R
func _gather() -> void:
	_cand.clear(); _cand_w.clear()
	_cand_at = focus
	var roads: Array = pack.region.roads
	for ri in roads.size():
		var r: Dictionary = roads[ri]
		if int(r.get("bridge", 0)) == 1 or int(r.rank) < 1: continue
		var P: Array = r.pts
		var inside := 0.0
		for i in range(0, P.size() - 2, 2):
			var m := Vector2((P[i] + P[i + 2]) * 0.5 - focus.x, (P[i + 1] + P[i + 3]) * 0.5 - focus.z)
			if m.length_squared() < DENSE_R * DENSE_R:
				inside += Vector2(P[i + 2] - P[i], P[i + 3] - P[i + 1]).length()
		if inside < 5.0: continue
		_cand.append(ri)
		_cand_w.append(inside)

func _lens(ri: int) -> PackedFloat32Array:
	if _len.has(ri): return _len[ri]
	var P: Array = pack.region.roads[ri].pts
	var L := PackedFloat32Array([0.0])
	for i in range(1, P.size() / 2):
		L.append(L[i - 1] + Vector2(P[i * 2] - P[i * 2 - 2], P[i * 2 + 1] - P[i * 2 - 1]).length())
	_len[ri] = L
	return L

## point and unit tangent (along increasing s) at distance s on road ri
func _sample(ri: int, s: float) -> Array:
	var P: Array = pack.region.roads[ri].pts
	var L := _lens(ri)
	var n := L.size()
	s = clampf(s, 0.0, L[n - 1])
	var i := L.bsearch(s) - 1
	i = clampi(i, 0, n - 2)
	var a := Vector2(P[i * 2], P[i * 2 + 1]); var b := Vector2(P[i * 2 + 2], P[i * 2 + 3])
	var seg := maxf(L[i + 1] - L[i], 0.001)
	return [a.lerp(b, (s - L[i]) / seg), (b - a) / seg]

func _pick_kind(rank: int) -> String:
	var ks: Array = []; var ws: Array = []
	for k in MIX:
		if rank < int(KINDS[k].min_rank): continue
		ks.append(k); ws.append(MIX[k] * (1.6 if k == "bus" and rank >= 4 else 1.0))
	if ks.is_empty(): return "bike"
	return ks[rng.pick_w(ws)]

func _spawn(anywhere: bool, hf: float) -> bool:
	if _cand.is_empty(): return false
	var have := {}
	for ag in agents: have[ag.ri] = have.get(ag.ri, 0) + 1
	var ws: Array = []
	var any := false
	for k in _cand.size():
		var rr: Dictionary = pack.region.roads[_cand[k]]
		var want: float = float(_cand_w[k]) / 100.0 * PER_100M[clampi(int(rr.rank), 0, 5)] * hf
		var deficit := maxf(0.0, want - float(have.get(_cand[k], 0)))
		ws.append(deficit)
		if deficit >= 0.5: any = true
	if not any: return false
	var ri: int = _cand[rng.pick_w(ws)]
	var r: Dictionary = pack.region.roads[ri]
	var L := _lens(ri)
	var total := L[L.size() - 1]
	if total < 8.0: return true
	var s := 0.0
	var smp: Array = []
	var ok := false
	for t in 8:
		s = rng.range_f(2.0, total - 2.0)
		smp = _sample(ri, s)
		var d := (smp[0] as Vector2).distance_to(Vector2(focus.x, focus.z))
		if d < DENSE_R and (anywhere or d > MIN_SPAWN_D): ok = true; break
	if not ok: return true
	var kind := _pick_kind(int(r.rank))
	var K: Dictionary = KINDS[kind]
	var oneway := int(r.get("oneway", 0)) == 1
	var dir := 1 if oneway or rng.next() < 0.5 else -1
	var w: float = r.w
	var lat := _lane(kind, w, oneway)
	# keep clear of others
	for b in agents:
		if b.ri == ri and b.dir == dir and absf(b.s - s) < (b.len + K.len) * 0.5 + 1.5 and absf(b.lat - lat) < (b.w + K.w) * 0.5 + 0.2:
			return true
	var rank := int(r.rank)
	var vmax: float = K.v * [0.45, 0.55, 0.7, 0.85, 1.0, 1.0][clampi(rank, 0, 5)] * rng.range_f(0.8, 1.15)
	var a := {"kind": kind, "ri": ri, "dir": dir, "s": s, "lat": lat, "lat_t": lat, "v": vmax * rng.range_f(0.5, 1.0), "v0": vmax,
		"len": K.len, "w": K.w, "yaw": 0.0, "dist": rng.next() * 50.0, "next": -1, "next_dir": 1, "blink": 0.0, "wait": 0.0,
		"node": null, "seed": rng.range_i(1, 999999), "honk": 0.0, "brake": 0.0, "lean": 0.0, "d": 0.0}
	var t: Vector2 = smp[1] * dir
	a.yaw = atan2(-t.x, -t.y)
	a.paint = VehicleModel.paint_for(kind, a.seed)[0]
	a.riders = _make_riders(kind, rng)
	a.xf = Transform3D(Basis(Vector3.UP, a.yaw), Vector3(smp[0].x, RegionBuilder.ROAD_Y, smp[0].y))
	agents.append(a)
	stats.spawned += 1
	return true

## lateral offset from the centreline (positive = left of travel). Two-wheelers hug the left edge
## and spread out; cars and buses keep nearer the middle of their half.
func _lane(kind: String, w: float, oneway: bool) -> float:
	var half := w * 0.5
	var K: Dictionary = KINDS[kind]
	if oneway:
		return clampf(rng.range_f(-half + K.w * 0.5 + 0.3, half - K.w * 0.5 - 0.3), -half, half)
	var lo: float = 0.3 + K.w * 0.5
	var hi: float = maxf(lo, half - K.w * 0.5 - 0.25)
	var t := rng.next()
	if kind in ["bike", "scooter"]: t = sqrt(t)          # bias towards the kerb
	elif kind == "bus": t = 0.5 + t * 0.3
	return lerpf(lo, hi, t)

func _road_half(ri: int) -> float:
	return float(pack.region.roads[ri].w) * 0.5

func _step_all(dt: float) -> void:
	# group by (road, direction) for leader search
	var groups := {}
	for a in agents:
		var k: int = a.ri * 2 + (1 if a.dir > 0 else 0)
		if not groups.has(k): groups[k] = []
		groups[k].append(a)
	var dead: Array = []
	for a in agents:
		var K: Dictionary = KINDS[a.kind]
		var L := _lens(a.ri)
		var total := L[L.size() - 1]
		var to_end: float = (total - a.s) if a.dir > 0 else a.s
		# leader: nearest overlapping vehicle ahead on the same road and direction
		var gap := 1e9; var v_lead := 0.0
		var blocked_lat := []
		for b in groups[a.ri * 2 + (1 if a.dir > 0 else 0)]:
			if b == a: continue
			var ds: float = (b.s - a.s) * a.dir
			if ds <= 0.0 or ds > 45.0: continue
			var g: float = ds - (a.len + b.len) * 0.5
			if absf(b.lat - a.lat) < (a.w + b.w) * 0.5 + 0.25:
				if g < gap: gap = g; v_lead = b.v
			if g < 12.0: blocked_lat.append([b.lat, b.w])
		# the player (on foot or driving) is an obstacle too
		var pos2: Vector2 = _sample(a.ri, a.s)[0]
		var tan2: Vector2 = _sample(a.ri, a.s)[1] * a.dir
		var left := Vector2(tan2.y, -tan2.x)
		var me: Vector2 = pos2 + left * a.lat
		for o in obstacles:
			var rel := Vector2(o.x, o.z) - me
			var ahead := rel.dot(tan2)
			if ahead > 0.0 and ahead < 25.0 and absf(rel.dot(left)) < a.w * 0.5 + 1.0:
				var g: float = ahead - a.len * 0.5 - 1.2
				if g < gap: gap = g; v_lead = 0.0
				if g < 10.0 and a.honk <= 0.0:
					a.honk = rng.range_f(1.5, 4.0)
					if sound and a.d < 150.0: sound.honk(a.kind, (a.xf as Transform3D).origin)
		# slow for the junction at the end of the road (turning traffic, crossing streams)
		var v0: float = a.v0
		if to_end < 18.0: v0 = minf(v0, lerpf(4.0, a.v0, to_end / 18.0))
		# IDM
		var s0 := 1.2 if a.kind in ["bike", "scooter"] else 1.8
		var dv: float = a.v - v_lead
		var sstar: float = s0 + maxf(0.0, a.v * K.T + a.v * dv / (2.0 * sqrt(K.a * K.b)))
		var acc: float = K.a * (1.0 - pow(a.v / maxf(v0, 0.1), 4.0) - pow(sstar / maxf(gap, 0.1), 2.0))
		acc = clampf(acc, -8.0, K.a)
		# weave: two-wheelers and autos look for a lateral gap around a slower leader
		if K.weave > 0.0 and gap < 14.0 and v_lead < a.v0 * 0.8 and rng.next() < K.weave * dt * 3.0:
			_weave(a, blocked_lat)
		a.v = maxf(0.0, a.v + acc * dt)
		a.brake = 1.0 if acc < -1.2 or a.v < 0.2 else 0.0
		var lat_rate := 0.9 if a.kind in ["bike", "scooter"] else 0.5
		a.lat = move_toward(a.lat, a.lat_t, lat_rate * dt)
		a.s += a.v * dt * a.dir
		a.dist += a.v * dt
		a.honk = maxf(0.0, a.honk - dt)
		# pick the next road in time to signal the turn
		if a.next < 0 and to_end < 35.0: _choose_next(a)
		if (a.dir > 0 and a.s >= total) or (a.dir < 0 and a.s <= 0.0):
			if not _advance(a): dead.append(a); continue
		_pose(a, dt)
		if a.d > DESPAWN_R: dead.append(a)
	for a in dead:
		_release(a)
		agents.erase(a)
	_render()

func _weave(a: Dictionary, blocked: Array) -> void:
	var half := _road_half(a.ri)
	var oneway := int(pack.region.roads[a.ri].get("oneway", 0)) == 1
	var lo: float = (-half if oneway else -0.6) + a.w * 0.5 + 0.2   # two-way: may poke a little over the centre line
	var hi: float = half - a.w * 0.5 - 0.15
	var best := INF; var best_lat: float = a.lat
	for cand in [a.lat - 1.2, a.lat + 1.2, a.lat - 2.2, a.lat + 2.2, lo, hi]:
		var c := clampf(cand, lo, hi)
		var free := true
		for b in blocked:
			if absf(b[0] - c) < (a.w + b[1]) * 0.5 + 0.2: free = false; break
		if free and absf(c - a.lat) < best:
			best = absf(c - a.lat); best_lat = c
	a.lat_t = best_lat

func _choose_next(a: Dictionary) -> void:
	var r: Dictionary = pack.region.roads[a.ri]
	var n: int = r.pts.size() / 2
	var j: int = int(r.j[n - 1] if a.dir > 0 else r.j[0])
	a.next = -2
	if j < 0: return
	var min_rank := int(KINDS[a.kind].min_rank)
	var tan_in: Vector2 = _sample(a.ri, a.s)[1] * a.dir
	var cands: Array = []; var ws: Array = []; var dirs: Array = []
	for rv in pack.region.junctions[j].roads:
		var ri := int(rv)
		if ri == a.ri: continue
		var rd: Dictionary = pack.region.roads[ri]
		if int(rd.rank) < min_rank or int(rd.get("bridge", 0)) == 1: continue
		var d := 1 if int(rd.j[0]) == j else -1
		if int(rd.get("oneway", 0)) == 1 and d < 0: continue
		var L := _lens(ri)
		var tan_out: Vector2 = _sample(ri, 0.5 if d > 0 else L[L.size() - 1] - 0.5)[1] * d
		var straight := tan_in.dot(tan_out)
		cands.append(ri); dirs.append(d)
		ws.append((1.0 + float(rd.rank)) * (1.0 + maxf(straight, 0.0) * 2.0))
	if cands.is_empty(): return
	var k := rng.pick_w(ws)
	a.next = cands[k]; a.next_dir = dirs[k]
	var L2 := _lens(a.next)
	var t_out: Vector2 = _sample(a.next, 0.5 if a.next_dir > 0 else L2[L2.size() - 1] - 0.5)[1] * a.next_dir
	var turn := tan_in.cross(t_out)       # >0: turning right in x-east/z-south coordinates
	a.blink = 0.0 if absf(turn) < 0.45 else (1.0 if turn > 0.0 else -1.0)

func _advance(a: Dictionary) -> bool:
	if a.next == -1: _choose_next(a)
	if a.next < 0:
		# dead end: turn round on two-way streets (despawning in view looks wrong), else vanish
		if int(pack.region.roads[a.ri].get("oneway", 0)) == 1: return false
		var Ld := _lens(a.ri)
		a.dir = -a.dir
		a.s = clampf(a.s, 0.5, Ld[Ld.size() - 1] - 0.5)
		a.v = minf(a.v, 2.0)
		a.next = -1
		a.blink = 0.0
		return true
	var L := _lens(a.ri)
	var over: float = (a.s - L[L.size() - 1]) if a.dir > 0 else -a.s
	a.ri = a.next; a.dir = a.next_dir
	var L2 := _lens(a.ri)
	a.s = over if a.dir > 0 else L2[L2.size() - 1] - over
	var half := _road_half(a.ri)
	var oneway := int(pack.region.roads[a.ri].get("oneway", 0)) == 1
	a.lat_t = clampf(a.lat_t, (-half if oneway else 0.2) + a.w * 0.5, half - a.w * 0.5 - 0.15)
	var rank := int(pack.region.roads[a.ri].rank)
	a.v0 = KINDS[a.kind].v * [0.45, 0.55, 0.7, 0.85, 1.0, 1.0][clampi(rank, 0, 5)] * rng.range_f(0.85, 1.1)
	a.next = -1
	a.blink = 0.0
	return true

func _pose(a: Dictionary, dt: float) -> void:
	var smp := _sample(a.ri, a.s)
	var t: Vector2 = smp[1] * a.dir
	var left := Vector2(t.y, -t.x)
	var p: Vector2 = smp[0] + left * a.lat
	var yaw_t := atan2(-t.x, -t.y)
	var prev_yaw: float = a.yaw
	a.yaw = lerp_angle(a.yaw, yaw_t, clampf(dt * (2.0 + a.v * 0.6), 0.0, 1.0))
	var yaw_rate := wrapf(a.yaw - prev_yaw, -PI, PI) / maxf(dt, 0.001)
	a.yaw_rate = yaw_rate
	var lean := 0.0
	if a.kind in ["bike", "scooter"]:
		lean = clampf(-yaw_rate * a.v / 9.81, -0.6, 0.6)
	a.lean = lerpf(a.lean, lean, clampf(dt * 5.0, 0.0, 1.0))
	a.xf = Transform3D(Basis.from_euler(Vector3(0, a.yaw, a.lean)), Vector3(p.x, RegionBuilder.ROAD_Y, p.y))
	a.d = Vector2(p.x - focus.x, p.y - focus.z).length()

func _pose_node(a: Dictionary) -> void:
	var body: Node3D = a.node
	body.transform = a.xf
	var vm: VehicleModel = body.get_meta("model")
	# wheels: spin with distance, front wheels steer with the yaw rate
	var wb: float = a.len * 0.6
	var steer := clampf(atan(float(a.yaw_rate) * wb / maxf(a.v, 0.5)), -0.6, 0.6)
	for w in vm.wheels:
		var r: float = w.get_meta("r", 0.3)
		var front: bool = w.get_meta("front", false)
		w.rotation = Vector3(-a.dist / r, steer if front else 0.0, 0.0)
	vm.set_param("brake", a.brake)
	vm.set_param("blink", a.blink)
	var eng: AudioStreamPlayer3D = body.get_node_or_null("engine")
	if eng: eng.pitch_scale = 0.75 + clampf(float(a.v) / float(KINDS[a.kind].v), 0.0, 1.2) * 0.8

## who rides: Chennai two-wheelers often carry a pillion (often a woman riding behind), autos carry
## up to three passengers; car and bus occupants are behind tinted glass (not drawn yet)
func _make_riders(kind: String, r: Rng) -> Array:
	var out: Array = []
	match kind:
		"bike":
			out.append(_rider("m" if r.next() < 0.88 else "f", "ride_bike", 0.0, r))
			if r.next() < 0.35: out.append(_rider("f" if r.next() < 0.6 else "m", "ride_pillion", 0.0, r))
		"scooter":
			out.append(_rider("m" if r.next() < 0.55 else "f", "ride_scooter", 0.0, r))
			if r.next() < 0.25: out.append(_rider("f" if r.next() < 0.5 else "m", "ride_pillion", 0.0, r))
		"auto":
			out.append(_rider("m", "ride_auto", 0.0, r))
			var n := r.pick_w([3.0, 4.0, 3.0, 1.5])
			var xs: Array = [[], [0.0], [-0.27, 0.27], [-0.34, 0.0, 0.34]][n]
			for x in xs: out.append(_rider("", "ride_pass", x, r))
	return out

func _rider(sex: String, clip: String, x: float, r: Rng) -> Dictionary:
	var c: Array = []
	for i in _specs.size():
		var sp: Dictionary = _specs[i]
		if String(sp.id).begins_with("child"): continue
		if sex != "" and sp.sex != sex: continue
		if clip in ["ride_bike", "ride_auto"] and sp.dress in ["shirt_lungi"] and r.next() < 0.5: continue
		c.append(i)
	var si: int = c[int(r.next() * c.size()) % c.size()] if not c.is_empty() else 0
	var seed := r.range_i(1, 999999)
	var app := HumanActor.appearance_for(_specs[si], Rng.new(seed))
	return {"si": si, "clip": clip, "x": x, "seed": seed, "app": app, "actor": null}

## tiers: the nearest MAX_NEAR within NEAR_R get pooled bodies with colliders and skeletal riders;
## the rest are low-detail MultiMesh bodies with VAT riders (drawn by the crowd)
func _render() -> void:
	var order := agents.duplicate()
	order.sort_custom(func(x, y): return x.d < y.d)
	var near := {}
	for k in mini(order.size(), MAX_NEAR):
		if order[k].d < NEAR_R: near[order[k]] = true
	var bufs := {}
	for k in KINDS: bufs[k] = PackedFloat32Array()
	var extra: Array = []
	for a in agents:
		if near.has(a):
			if a.node == null: _acquire(a)
			_pose_node(a)
			continue
		if a.node != null: _release(a)
		var xf: Transform3D = a.xf
		var b := xf.basis
		var c: Color = a.paint
		bufs[a.kind].append_array([b.x.x, b.y.x, b.z.x, xf.origin.x, b.x.y, b.y.y, b.z.y, xf.origin.y, b.x.z, b.y.z, b.z.z, xf.origin.z, c.r, c.g, c.b, 1.0])
		if crowd and a.d < 160.0:
			for rd in a.riders:
				extra.append([rd.si, xf * Transform3D(Basis(), _seat(rd)), rd.app, rd.clip])
	for k in KINDS:
		var mm: MultiMesh = _mm[k].multimesh
		var buf: PackedFloat32Array = bufs[k]
		var cnt := buf.size() / 16
		if mm.instance_count != cnt: mm.instance_count = cnt
		if cnt > 0: mm.buffer = buf
	if crowd: crowd.extra = extra
	stats["near"] = near.size()

static var _rides := {}
func _seat(rd: Dictionary) -> Vector3:
	if _rides.is_empty():
		var d = CityPack.load_json("res://assets/humans/rides.json")
		_rides = d if d else {}
	var h: Array = _rides.get(rd.clip, {"hips": [0, 1, 0]}).hips
	return Vector3(float(h[0]) + float(rd.x), 0.0, float(h[2]))

func _acquire(a: Dictionary) -> void:
	var pool: Array = pools.get(a.kind, [])
	var body: AnimatableBody3D
	if pool.is_empty():
		body = AnimatableBody3D.new()
		body.sync_to_physics = false
		var vm := VehicleModel.make(a.kind, a.seed)
		body.add_child(vm)
		body.set_meta("model", vm)
		var info := vm.wheel_info()
		var zmid := 0.0
		for w in info: zmid += w.p.z / maxf(1.0, info.size())
		for w in info:
			w.node.set_meta("r", w.r)
			w.node.set_meta("front", w.p.z < zmid)
		body.add_child(Soundscape.engine_player(a.kind))
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		var K: Dictionary = KINDS[a.kind]
		var h := 3.0 if a.kind == "bus" else (1.6 if a.kind in ["auto", "hatch"] else 1.1)
		box.size = Vector3(K.w, h - 0.3, K.len)
		cs.shape = box
		cs.position = Vector3(0, 0.3 + (h - 0.3) * 0.5, 0)
		body.add_child(cs)
		body.collision_layer = 1
		body.collision_mask = 0
		add_child(body)
	else:
		body = pool.pop_back()
		body.visible = true
		body.process_mode = Node.PROCESS_MODE_INHERIT
		var vm: VehicleModel = body.get_meta("model")
		vm.recolour(a.seed)
	a.node = body
	body.transform = a.xf
	var eng: AudioStreamPlayer3D = body.get_node_or_null("engine")
	if eng: eng.play(rng.next() * 1.5)
	body.collision_layer = 1
	var model: VehicleModel = body.get_meta("model")
	for rd in a.riders:
		var act: HumanActor = null
		var pl: Array = _actor_pool.get(rd.si, [])
		if pl.is_empty():
			act = HumanActor.new()
			model.add_child(act)
			act.build(_specs[rd.si], rd.app, rd.seed)
		else:
			act = pl.pop_back()
			act.get_parent().remove_child(act)
			model.add_child(act)
			act.reshade(rd.app, rd.seed)
		act.visible = true
		act.ride(rd.clip, rd.x)
		rd.actor = act

func _release(a: Dictionary) -> void:
	var body: Node3D = a.node
	if body == null: return
	body.visible = false
	body.position = Vector3(0, -100, 0)
	var eng: AudioStreamPlayer3D = body.get_node_or_null("engine")
	if eng: eng.stop()
	body.collision_layer = 0
	for rd in a.riders:
		var act: HumanActor = rd.actor
		if act == null: continue
		act.visible = false
		if not _actor_pool.has(rd.si): _actor_pool[rd.si] = []
		_actor_pool[rd.si].append(act)
		rd.actor = null
	if not pools.has(a.kind): pools[a.kind] = []
	pools[a.kind].append(body)
	a.node = null

func clear() -> void:
	for a in agents: _release(a)
	agents.clear()
