class_name RegionBuilder
extends RefCounted
## Region-level geometry from meta.json: ground (with tank cut-outs and the beach slope),
## OSM area polygons, roads with junction patches, footpaths and kerbs, stepped temple tanks,
## and the sea. Port of src/world/region.ts. Pure data → MB; meshes are made by the caller.

const BEACH_IN := 70.0
const SEA_LEVEL := -0.35
const ROAD_Y := 0.03
const AREA_KIND := {"park": 1, "ground": 2, "beach": 3, "religious": 4, "cemetery": 5, "construction": 2, "parking": 7}

var pack: CityPack
var ground := MB.new(false)    # c0 = (kind, tint, 0, 0)
var roads := MB.new(false)     # c0 = (wear, rank, width, rnd); uv = (metres along, -1..1 across)
var walks := MB.new(false)     # footpaths/kerbs/tank granite; generic material c0 = (type, rough, emissive, rnd)
var water := MB.new(false)
var sea := MB.new(false)       # c0.x = distance offshore
var tanks: Array[PackedVector2Array] = []
var tank_colliders := PackedVector3Array()   # triangle soup
var kerb_colliders := PackedVector3Array()
var junction_r := PackedFloat32Array()

func _init(p: CityPack) -> void:
	pack = p

func build() -> void:
	_find_tanks()
	_build_ground()
	_build_roads()
	_build_sea()

static func poly_area(p: PackedVector2Array) -> float:
	var a := 0.0
	for i in p.size():
		var j := (i + 1) % p.size()
		a += p[i].x * p[j].y - p[j].x * p[i].y
	return a * 0.5

func _find_tanks() -> void:
	for a in pack.region.areas:
		if a.k != "water": continue
		var pts := CityPack.pts2(a.pts)
		if pts.size() >= 3 and absf(poly_area(pts)) < 120000.0:
			tanks.append(pts)

func _in_tank(p: Vector2) -> bool:
	for t in tanks:
		if Geometry2D.is_point_in_polygon(p, t): return true
	return false

# ------------------------------------------------------------------------------------------ ground
func _build_ground() -> void:
	var b := pack.bounds
	var M := 600.0
	var x0 := b.position.x - M; var x1 := b.end.x + M; var z0 := b.position.y - M; var z1 := b.end.y + M
	var coast := pack.has_coast()
	var white := Color(1, 1, 1)
	var tank_boxes: Array[Rect2] = []
	for t in tanks:
		var r := Rect2(t[0], Vector2.ZERO)
		for p in t: r = r.expand(p)
		tank_boxes.append(r.grow(2.0))
	var T := 50.0
	var z := z0
	while z < z1:
		var zb := minf(z + T, z1)
		var xe_a := minf(x1, pack.coast_x(z) - BEACH_IN) if coast else x1
		var xe_b := minf(x1, pack.coast_x(zb) - BEACH_IN) if coast else x1
		var x := x0
		while x < minf(xe_a, xe_b) - T:
			var tile := Rect2(x, z, T, zb - z)
			var hit := false
			for r in tank_boxes:
				if r.intersects(tile): hit = true
			if hit:
				# 10 m sub-tiles; those crossing a tank edge are clipped against the tank polygon
				var sub := 10.0
				var sz := z
				while sz < zb - 0.01:
					var sx := x
					var sz1 := minf(sz + sub, zb)
					while sx < x + T - 0.01:
						var cellp := PackedVector2Array([Vector2(sx, sz), Vector2(sx + sub, sz), Vector2(sx + sub, sz1), Vector2(sx, sz1)])
						var pieces: Array = [cellp]
						for ti in tanks.size():
							if not tank_boxes[ti].intersects(Rect2(sx, sz, sub, sz1 - sz)): continue
							var next: Array = []
							for pc in pieces:
								for q in Geometry2D.clip_polygons(pc, tanks[ti]):
									if signf(poly_area(q)) == signf(poly_area(cellp)): next.append(q)
							pieces = next
						for pc in pieces:
							var tr := Geometry2D.triangulate_polygon(pc)
							if not tr.is_empty(): ground.polygon(pc, tr, 0.0, true, white, Vector4.ZERO)
						sx += sub
					sz = sz1
			else:
				ground.quad(Vector3(x, 0, z), Vector3(x + T, 0, z), Vector3(x + T, 0, zb), Vector3(x, 0, zb), Vector3.UP, white, Vector4.ZERO)
			x += T
		# last trapezoid up to the beach edge
		ground.quad(Vector3(x, 0, z), Vector3(xe_a, 0, z), Vector3(xe_b, 0, zb), Vector3(x, 0, zb), Vector3.UP, white, Vector4.ZERO)
		z = zb

	# outer ring to the horizon (coarse 500 m tiles), so the land never ends in view
	var O := 8000.0
	ground.quad(Vector3(x0 - O, 0, z0 - O), Vector3(x0, 0, z0 - O), Vector3(x0, 0, z1 + O), Vector3(x0 - O, 0, z1 + O), Vector3.UP, white, Vector4.ZERO)
	for band_ in [[z0 - O, z0], [z1, z1 + O]]:
		var zz0: float = band_[0]; var zz1: float = band_[1]
		var zq := zz0
		while zq < zz1:
			var zq1 := minf(zq + 500.0, zz1)
			var ea := minf(x1 + O, pack.coast_x(zq) - BEACH_IN) if coast else x1 + O
			var eb := minf(x1 + O, pack.coast_x(zq1) - BEACH_IN) if coast else x1 + O
			ground.quad(Vector3(x0, 0, zq), Vector3(ea, 0, zq), Vector3(eb, 0, zq1), Vector3(x0, 0, zq1), Vector3.UP, white, Vector4.ZERO)
			zq = zq1
	if not coast:
		ground.quad(Vector3(x1, 0, z0), Vector3(x1 + O, 0, z0), Vector3(x1 + O, 0, z1), Vector3(x1, 0, z1), Vector3.UP, white, Vector4.ZERO)

	# area polygons (park, beach, temple grounds…) slightly above ground, clamped off the beach strip
	for a in pack.region.areas:
		if not AREA_KIND.has(a.k): continue
		var k: int = AREA_KIND[a.k]
		var pts := CityPack.pts2(a.pts)
		if coast:
			for i in pts.size(): pts[i].x = minf(pts[i].x, pack.coast_x(pts[i].y) - BEACH_IN)
		if absf(poly_area(pts)) < 4.0: continue
		var tris := Geometry2D.triangulate_polygon(pts)
		if tris.is_empty(): continue
		var tint := 0.92 + Rng.hashf(pts.size() * 7 + int(pts[0].x)) * 0.16
		ground.polygon(pts, tris, 0.012 + k * 0.002, true, Color(tint, tint, tint), Vector4(k, 0, 0, 0))

	for t in tanks: _build_tank(t)

	if coast:
		var S := [-BEACH_IN, -40.0, -15.0, 0.0, 8.0, 20.0, 45.0]
		var zs: Array[float] = []
		var zz := z0 - O
		while zz <= z1 + O: zs.append(zz); zz += (20.0 if zz > z0 - 200.0 and zz < z1 + 200.0 else 250.0)
		for zi in zs.size() - 1:
			for si in S.size() - 1:
				var za: float = zs[zi]; var zb2: float = zs[zi + 1]; var sa: float = S[si]; var sb: float = S[si + 1]
				var kind := 6.0 if (sa + sb) * 0.5 > -12.0 else 3.0
				var q := [Vector3(pack.coast_x(za) + sa, _beach_y(sa), za), Vector3(pack.coast_x(za) + sb, _beach_y(sb), za),
					Vector3(pack.coast_x(zb2) + sb, _beach_y(sb), zb2), Vector3(pack.coast_x(zb2) + sa, _beach_y(sa), zb2)]
				var nrm: Vector3 = (q[1] - q[0]).cross(q[3] - q[0]).normalized()
				if nrm.y < 0: nrm = -nrm
				ground.quad(q[0], q[1], q[2], q[3], nrm, white, Vector4(kind, 1, 0, 0))
				tank_colliders.append_array([q[0], q[1], q[2], q[0], q[2], q[3]])

static func _beach_y(s: float) -> float:
	if s <= -BEACH_IN: return 0.0
	if s < 0.0: return -0.32 * (s + BEACH_IN) / BEACH_IN
	return -0.32 - (s / 45.0) * 1.6

static func inset(p: PackedVector2Array, d: float) -> PackedVector2Array:
	var n := p.size()
	var out := PackedVector2Array()
	var sgn := 1.0 if poly_area(p) > 0 else -1.0
	for i in n:
		var a := p[(i - 1 + n) % n]; var b := p[i]; var c := p[(i + 1) % n]
		var e1 := (b - a).normalized(); var e2 := (c - b).normalized()
		var n1 := Vector2(-e1.y, e1.x) * sgn; var n2 := Vector2(-e2.y, e2.x) * sgn
		var bis := (n1 + n2).normalized()
		var cosh := maxf(0.35, bis.dot(n1))
		out.append(b + bis * (d / cosh))
	return out

## Stepped granite tank (Kapaleeshwarar kulam): rim coping, 9 steps down to the water,
## kaavi-and-white striped parapet around the rim (STYLE_BIBLE §2, §7)
func _build_tank(ring: PackedVector2Array) -> void:
	# make the inset direction point inward regardless of winding
	if poly_area(inset(ring, 1.0)) * signf(poly_area(ring)) > absf(poly_area(ring)): ring.reverse()
	var steps := 9; var rise := 0.28; var tread := 0.55
	var granite := Color(0.95, 0.93, 0.9)
	var G := Vector4(10, 0.75, 0, 0)
	# rim coping (covers the jagged ground cut) + striped parapet wall outside it
	var outer := inset(ring, -1.4)
	for i in ring.size():
		var a0 := outer[i]; var a1 := outer[(i + 1) % ring.size()]; var b0 := ring[i]; var b1 := ring[(i + 1) % ring.size()]
		walks.quad(Vector3(a0.x, 0.06, a0.y), Vector3(a1.x, 0.06, a1.y), Vector3(b1.x, 0.06, b1.y), Vector3(b0.x, 0.06, b0.y), Vector3.UP, granite, G)
	_kaavi_wall(inset(ring, -1.6), 0.9)
	for s in steps:
		var inner := inset(ring, tread)
		var y_top := -s * rise; var y_bot := -(s + 1) * rise
		for i in ring.size():
			var a0 := ring[i]; var a1 := ring[(i + 1) % ring.size()]; var b0 := inner[i]; var b1 := inner[(i + 1) % inner.size()]
			var tq := [Vector3(a0.x, y_top, a0.y), Vector3(a1.x, y_top, a1.y), Vector3(b1.x, y_top, b1.y), Vector3(b0.x, y_top, b0.y)]
			walks.quad(tq[0], tq[1], tq[2], tq[3], Vector3.UP, granite, Vector4(10, 0.75, 0, Rng.hashf(i * 31 + s)))
			var d := b1 - b0
			var nrm := Vector3(-d.y, 0, d.x).normalized()
			var mid := (b0 + b1) * 0.5
			var cen := Vector2.ZERO
			for p in inner: cen += p
			cen /= inner.size()
			if Vector2(nrm.x, nrm.z).dot(cen - mid) < 0: nrm = -nrm
			var rq := [Vector3(b0.x, y_top, b0.y), Vector3(b1.x, y_top, b1.y), Vector3(b1.x, y_bot, b1.y), Vector3(b0.x, y_bot, b0.y)]
			walks.quad(rq[0], rq[1], rq[2], rq[3], nrm, Color(0.86, 0.84, 0.8), Vector4(10, 0.8, 0, 0))
			tank_colliders.append_array([tq[0], tq[1], tq[2], tq[0], tq[2], tq[3], rq[0], rq[1], rq[2], rq[0], rq[2], rq[3]])
		ring = inner
	var tris := Geometry2D.triangulate_polygon(ring)
	if not tris.is_empty():
		water.polygon(ring, tris, -steps * rise + 0.55, true, Color(1, 1, 1), Vector4.ZERO)

## low perimeter wall with vertical kaavi (red-ochre) and white stripes (STYLE_BIBLE §2)
func _kaavi_wall(ring: PackedVector2Array, h: float) -> void:
	var kaavi := Rng.hex_lin(pack.style.get("kaavi", "#b5442c"))
	var white := Rng.hex_lin("#f3efe6")
	for i in ring.size():
		var a := ring[i]; var b := ring[(i + 1) % ring.size()]
		var L := a.distance_to(b)
		if L < 0.5: continue
		var t := (b - a) / L
		var nrm := Vector3(t.y, 0, -t.x)
		var stripes := maxi(1, int(L / 0.55))
		for s in stripes:
			var p0 := a + t * (L * s / stripes); var p1 := a + t * (L * (s + 1) / stripes)
			var c := kaavi if s % 2 == 0 else white
			for side in [1.0, -1.0]:
				var o: Vector2 = Vector2(nrm.x, nrm.z) * 0.12 * side
				walks.quad(Vector3(p0.x + o.x, 0, p0.y + o.y), Vector3(p1.x + o.x, 0, p1.y + o.y), Vector3(p1.x + o.x, h, p1.y + o.y), Vector3(p0.x + o.x, h, p0.y + o.y), nrm * side, c, Vector4(13, 0.9, 0, 0))
			walks.quad(Vector3(p0.x - nrm.x * 0.12, h, p0.y - nrm.z * 0.12), Vector3(p1.x - nrm.x * 0.12, h, p1.y - nrm.z * 0.12), Vector3(p1.x + nrm.x * 0.12, h, p1.y + nrm.z * 0.12), Vector3(p0.x + nrm.x * 0.12, h, p0.y + nrm.z * 0.12), Vector3.UP, c * 0.92, Vector4(13, 0.9, 0, 0))
		kerb_colliders.append_array(_box_tris(a, b, 0.12, h))

static func _box_tris(a: Vector2, b: Vector2, half_w: float, h: float) -> PackedVector3Array:
	var t := (b - a).normalized()
	var nn := Vector2(-t.y, t.x) * half_w
	var c := [a + nn, b + nn, b - nn, a - nn]
	var out := PackedVector3Array()
	for i in 4:
		var p: Vector2 = c[i]; var q: Vector2 = c[(i + 1) % 4]
		out.append_array([Vector3(p.x, 0, p.y), Vector3(q.x, 0, q.y), Vector3(q.x, h, q.y), Vector3(p.x, 0, p.y), Vector3(q.x, h, q.y), Vector3(p.x, h, p.y)])
	out.append_array([Vector3(c[0].x, h, c[0].y), Vector3(c[1].x, h, c[1].y), Vector3(c[2].x, h, c[2].y), Vector3(c[0].x, h, c[0].y), Vector3(c[2].x, h, c[2].y), Vector3(c[3].x, h, c[3].y)])
	return out

# ------------------------------------------------------------------------------------------- roads
func drivable(r: Dictionary) -> bool:
	return int(r.rank) > 0 or r.cls == "pedestrian"

func _build_roads() -> void:
	var R: Array = pack.region.roads
	var J: Array = pack.region.junctions
	junction_r.resize(J.size())
	junction_r.fill(0.0)
	for r in R:
		if not drivable(r): continue
		for j in r.j:
			if j >= 0: junction_r[j] = maxf(junction_r[j], float(r.w) * 0.5)
	for ri in R.size():
		var r: Dictionary = R[ri]
		if not drivable(r): continue
		var P: Array = r.pts
		var n := P.size() / 2
		if n < 2: continue
		var rnd := Rng.new(int(r.id))
		var wear := minf(1.0, (0.55 if int(r.rank) <= 2 else 0.3) + rnd.next() * 0.4)
		var hw := float(r.w) * 0.5
		var acc := 0.0
		var left := PackedVector3Array(); var right := PackedVector3Array(); var us := PackedFloat32Array()
		for i in n:
			var p := Vector2(P[i * 2], P[i * 2 + 1])
			var a := p - Vector2(P[i * 2 - 2], P[i * 2 - 1]) if i > 0 else Vector2(P[i * 2 + 2], P[i * 2 + 3]) - p
			var b := Vector2(P[i * 2 + 2], P[i * 2 + 3]) - p if i < n - 1 else a
			var la := maxf(a.length(), 0.001)
			var t := (a / la + b / maxf(b.length(), 0.001)).normalized()
			var cos_half := maxf(0.5, (a / la).dot(t))
			var off := Vector2(-t.y, t.x) * (hw / cos_half)
			if i > 0: acc += la
			left.append(Vector3(p.x + off.x, ROAD_Y, p.y + off.y)); right.append(Vector3(p.x - off.x, ROAD_Y, p.y - off.y)); us.append(acc)
		var c0 := Vector4(wear, float(r.rank), float(r.w), rnd.next())
		for i in n - 1:
			roads.quad(left[i], right[i], right[i + 1], left[i + 1], Vector3.UP, Color(1, 1, 1), c0, Vector4.ZERO,
				Vector2(us[i], 1), Vector2(us[i], -1), Vector2(us[i + 1], -1), Vector2(us[i + 1], 1))
		if int(r.rank) >= 3: _footpaths(r, rnd)
	# junction patches (slightly raised to cover ribbon ends)
	for ji in J.size():
		var rad := junction_r[ji]
		var j: Dictionary = J[ji]
		if rad <= 0.0 or j.roads.size() < 2: continue
		var seg := 16
		var c := Vector3(j.p[0], ROAD_Y + 0.004, j.p[1])
		var c0 := Vector4(0.4, 3, rad * 2, 0)
		var base := roads.vert(c, Vector3.UP, Color(1, 1, 1), Vector2(0, 0), c0)
		for s in seg + 1:
			var ang := float(s) / seg * TAU
			roads.vert(c + Vector3(cos(ang), 0, sin(ang)) * rad * 1.08, Vector3.UP, Color(1, 1, 1), Vector2(0, 0.45), c0)
		for s in seg:
			roads.idx.append_array([base, base + 1 + s, base + 2 + s])
		roads._fix_last_tris(base, seg * 3)

func _footpaths(r: Dictionary, rnd: Rng) -> void:
	var P: Array = r.pts
	var n := P.size() / 2
	var hw := float(r.w) * 0.5
	var fw := rnd.range_f(1.8, 2.5) if int(r.rank) >= 5 else rnd.range_f(1.2, 1.8)
	var kerb_h := 0.17
	var paver := Rng.hex_lin("#8c8478" if rnd.next() < 0.5 else "#8a5a4a")
	var painted := int(r.rank) >= 5
	for i in n - 1:
		var a := Vector2(P[i * 2], P[i * 2 + 1]); var b := Vector2(P[i * 2 + 2], P[i * 2 + 3])
		var L := a.distance_to(b)
		if L < 1.0: continue
		var t := (b - a) / L
		var nn := Vector2(-t.y, t.x)
		var ja: int = r.j[i]; var jb: int = r.j[i + 1]
		var ta := junction_r[ja] + fw + 1.5 if ja >= 0 else 0.0
		var tb := junction_r[jb] + fw + 1.5 if jb >= 0 else 0.0
		if ta + tb >= L - 0.5: continue
		var s0 := a + t * ta
		var len := L - ta - tb
		for side in [-1.0, 1.0]:
			if rnd.next() < 0.12: continue   # missing stretches are common
			var o0: float = hw * side; var o1: float = (hw + fw) * side
			var P3 := func(s: float, o: float, y: float) -> Vector3: var q := s0 + t * s + nn * o; return Vector3(q.x, y, q.y)
			walks.quad(P3.call(0, o0, kerb_h), P3.call(len, o0, kerb_h), P3.call(len, o1, kerb_h), P3.call(0, o1, kerb_h), Vector3.UP, paver,
				Vector4(14, 0.85, 0, rnd.next()), Vector4.ZERO, Vector2(0, 0), Vector2(len, 0), Vector2(len, fw), Vector2(0, fw))
			var kc := Color(0.5, 0.42, 0.05) if painted else Color(0.45, 0.44, 0.42)
			walks.quad(P3.call(0, o0, 0), P3.call(len, o0, 0), P3.call(len, o0, kerb_h), P3.call(0, o0, kerb_h), Vector3(-nn.x * side, 0, -nn.y * side), kc,
				Vector4(15 if painted else 5, 0.8, 0, rnd.next()), Vector4.ZERO, Vector2(0, 0), Vector2(len, 0), Vector2(len, kerb_h), Vector2(0, kerb_h))
			var q0: Vector3 = P3.call(0, o0, kerb_h); var q1: Vector3 = P3.call(len, o0, kerb_h); var q2: Vector3 = P3.call(len, o1, kerb_h); var q3: Vector3 = P3.call(0, o1, kerb_h)
			var k0: Vector3 = P3.call(0, o0, 0); var k1: Vector3 = P3.call(len, o0, 0)
			kerb_colliders.append_array([q0, q1, q2, q0, q2, q3, k0, k1, q1, k0, q1, q0])

# --------------------------------------------------------------------------------------------- sea
func _build_sea() -> void:
	if not pack.has_coast(): return
	var b := pack.bounds
	var S := [-8.0, 0.0, 6.0, 12.0, 20.0, 30.0, 45.0, 65.0, 90.0, 130.0, 190.0, 280.0, 420.0, 650.0, 1000.0, 1600.0, 2600.0, 4000.0]
	var zs: Array[float] = []
	var z := b.position.y - 8000.0
	while z <= b.end.y + 8000.0: zs.append(z); z += (25.0 if z > b.position.y - 1500.0 and z < b.end.y + 1500.0 else 250.0)
	for zi in zs.size() - 1:
		for si in S.size() - 1:
			var za := zs[zi]; var zb := zs[zi + 1]; var sa: float = S[si]; var sb: float = S[si + 1]
			var cxa := pack.coast_x(za); var cxb := pack.coast_x(zb)
			sea.quad(Vector3(cxa + sa, SEA_LEVEL, za), Vector3(cxa + sb, SEA_LEVEL, za), Vector3(cxb + sb, SEA_LEVEL, zb), Vector3(cxb + sa, SEA_LEVEL, zb),
				Vector3.UP, Color(1, 1, 1), Vector4(0, 0, 0, 0), Vector4.ZERO,
				Vector2(maxf(0, sa - 2), 0), Vector2(maxf(0, sb - 2), 0), Vector2(maxf(0, sb - 2), 0), Vector2(maxf(0, sa - 2), 0))
