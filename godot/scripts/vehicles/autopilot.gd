class_name Autopilot
extends RefCounted
## Follows the OSM road graph with pure-pursuit steering and a speed controller. Used by the
## harness drive test now and as the seed of the traffic AI (Phase 3).

var pack: CityPack
var road := -1
var dir := 1            # +1 along the polyline, -1 against it
var idx := 0            # next point index
var target_speed := 9.0
var rng := Rng.new(7)
var lane := 0.35        # keep left (India drives on the left): fraction of half-width
var distance := 0.0

func _init(p: CityPack, seed := 7) -> void:
	pack = p
	rng = Rng.new(seed)

func _pts(ri: int) -> Array:
	return pack.region.roads[ri].pts

func start_at(pos: Vector3) -> void:
	var rr := pack.nearest_road(pos.x, pos.z, 200.0, 2)
	if rr.is_empty(): return
	road = rr.ri
	dir = 1
	idx = rr.seg + 1

func _point(ri: int, i: int) -> Vector2:
	var P := _pts(ri)
	return Vector2(P[i * 2], P[i * 2 + 1])

## choose the next road at the end of the current one (prefer bigger roads, avoid U-turns)
func _next_road() -> void:
	var r: Dictionary = pack.region.roads[road]
	var n: int = r.pts.size() / 2
	var j: int = r.j[n - 1] if dir > 0 else r.j[0]
	if j < 0:
		dir = -dir
		idx = n - 2 if dir < 0 else 1
		return
	var cands: Array = []
	var weights: Array = []
	for ri in pack.region.junctions[j].roads:
		if ri == road: continue
		var rd: Dictionary = pack.region.roads[ri]
		if int(rd.rank) < 2: continue
		cands.append(ri)
		weights.append(1.0 + float(rd.rank))
	if cands.is_empty():
		dir = -dir
		idx = n - 2 if dir < 0 else 1
		return
	var ri: int = cands[rng.pick_w(weights)]
	var rd: Dictionary = pack.region.roads[ri]
	var m: int = rd.pts.size() / 2
	road = ri
	if rd.j[0] == j: dir = 1; idx = 1
	else: dir = -1; idx = m - 2

func drive(v: Vehicle, dt: float) -> void:
	if road < 0:
		start_at(v.global_position)
		if road < 0: return
	var pos := Vector2(v.global_position.x, v.global_position.z)
	var P := _pts(road)
	var n := P.size() / 2
	# advance waypoint when close
	var tgt := _point(road, idx)
	var prev := _point(road, clampi(idx - dir, 0, n - 1))
	var seg := (tgt - prev).normalized()
	var w: float = pack.region.roads[road].w
	var left := Vector2(seg.y, -seg.x)   # India keeps left; left of travel in x-east/z-south coords
	var aim := tgt + left * w * 0.5 * lane
	if pos.distance_to(tgt) < 6.0:
		idx += dir
		if idx < 0 or idx >= n: _next_road()
	# lookahead point
	var la := aim
	var fwd3 := -v.global_basis.z
	var fwd := Vector2(fwd3.x, fwd3.z).normalized()
	var to := (la - pos)
	var ang := fwd.angle_to(to.normalized())
	v.steer = clampf(ang * 1.6, -1.0, 1.0)
	var spd: float = v.linear_velocity.length()
	var want := target_speed * (1.0 - clampf(absf(ang) / 1.2, 0.0, 0.7))
	v.throttle = clampf((want - spd) * 0.6, 0.0, 1.0)
	v.brake = clampf((spd - want) * 0.4, 0.0, 1.0)
	v.handbrake = false
	distance += spd * dt
