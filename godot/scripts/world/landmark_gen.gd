class_name LandmarkGen
extends RefCounted
## Dravidian temple architecture from the region's derived `structures` (tools/osm/infill.py):
## gopurams (granite base with entrance passage, tapering stucco tiers crowded with polychrome
## figures and niches, barrel-vault crown with gold kalasams), the sanctum vimana, and the
## kaavi-and-white striped compound wall (STYLE_BIBLE §2, §7). Kapaleeshwarar's east
## rajagopuram is 7 tiers / ~37 m; the west gopuram 5 tiers.

const GM := BuildingGen.GM
const POLY := ["#2b6cb0", "#2f9e44", "#c92a2a", "#f2c94c", "#e88aa8", "#f3efe6", "#1c7ed6", "#e67700", "#7048e8", "#0ca678"]
const TIER_BODY := ["#efe6cf", "#d9e7f2", "#e8dcc0", "#f3efe6"]

var mb := MB.new(false)
var colliders := PackedVector3Array()
var r := Rng.new(1)

func build(structures: Array, kaavi: Color) -> void:
	# gopuram footprints first so compound walls can leave the gateways open
	var gates: Array = []
	for s in structures:
		if s.type == "gopuram":
			gates.append(s)
			_gopuram(s)
		elif s.type == "vimana":
			_vimana(s)
	for s in structures:
		if s.type == "compound": _compound(s, gates, kaavi)

func _frame(s: Dictionary) -> Array:
	var c := Vector3(s.p[0], 0, s.p[1])
	var n := Vector3(s.n[0], 0, s.n[1]).normalized()
	var t := Vector3(-n.z, 0, n.x)
	return [c, t, n, atan2(n.x, n.z)]

func _box(c: Vector3, h: Vector3, rot: float, col: Color, type: int, rough := 0.85, solid := false) -> void:
	mb.box(c, h, rot, col, Vector4(type, rough, 0, r.next()))
	if solid:
		var cs := cos(rot); var sn := sin(rot)
		var corners := []
		for q in [[-1, -1], [1, -1], [1, 1], [-1, 1]]:
			corners.append(Vector2(c.x + q[0] * h.x * cs + q[1] * h.z * sn, c.z - q[0] * h.x * sn + q[1] * h.z * cs))
		for i in 4:
			var a: Vector2 = corners[i]; var b: Vector2 = corners[(i + 1) % 4]
			var y0 := c.y - h.y; var y1 := c.y + h.y
			colliders.append_array([Vector3(a.x, y0, a.y), Vector3(b.x, y0, b.y), Vector3(b.x, y1, b.y), Vector3(a.x, y0, a.y), Vector3(b.x, y1, b.y), Vector3(a.x, y1, a.y)])

func _gopuram(s: Dictionary) -> void:
	r = Rng.new(int(s.p[0] * 31 + s.p[1] * 17))
	var f := _frame(s)
	var c: Vector3 = f[0]; var t: Vector3 = f[1]; var n: Vector3 = f[2]; var rot: float = f[3]
	var W: float = s.w; var D: float = s.d; var H: float = s.h; var tiers: int = s.tiers
	var hb := clampf(H * 0.22, 4.5, 9.0)
	var roof_h := H * 0.12
	var granite := Rng.hex_lin("#8a8580")
	var P := func(u: float, y: float, v: float) -> Vector3: return c + t * u + Vector3.UP * y + n * v
	# ---- granite base storey with the entrance passage (doorway ~ W/5 wide)
	var door_w := maxf(2.4, W * 0.17); var door_h := hb * 0.72
	var side_w := (W - door_w) * 0.5
	for sd in [-1.0, 1.0]:
		_box(P.call(sd * (door_w * 0.5 + side_w * 0.5), hb * 0.5, 0), Vector3(side_w * 0.5, hb * 0.5, D * 0.5), rot, granite, GM.GRANITE, 0.75, true)
	_box(P.call(0, door_h + (hb - door_h) * 0.5, 0), Vector3(door_w * 0.5, (hb - door_h) * 0.5, D * 0.5), rot, granite, GM.GRANITE, 0.75)
	# huge wooden doors folded back inside the passage
	for sd in [-1.0, 1.0]:
		_box(P.call(sd * door_w * 0.47, door_h * 0.5, D * 0.2), Vector3(0.08, door_h * 0.5, door_w * 0.25), rot, Rng.hex_lin("#3b2616"), GM.WOOD)
	# mouldings (adhisthana bands) and pilasters on the outer faces
	for k in 4:
		var y := 0.4 + k * hb * 0.24
		for sd in [-1.0, 1.0]:
			_box(P.call(sd * (door_w * 0.5 + side_w * 0.5), y, 0), Vector3(side_w * 0.5 + 0.08, 0.09, D * 0.5 + 0.08), rot, granite * 0.92, GM.GRANITE)
	for face in [-1.0, 1.0]:
		var nb := int(W / 1.6)
		for i in nb:
			var u := -W * 0.5 + (i + 0.5) * W / nb
			if absf(u) < door_w * 0.55: continue
			_box(P.call(u, hb * 0.5, face * (D * 0.5 + 0.06)), Vector3(0.18, hb * 0.48, 0.06), rot, granite * 1.05, GM.GRANITE)
	# ---- tapering stucco tiers: battered (frustum) bodies, cornice, a parapet of miniature shrines
	# (kuta at the corners, shala in the middle, panjaras between), and sculpted figures in each bay
	var y := hb
	var tier_h := (H - hb - roof_h) / tiers
	var body := Rng.hex_lin(r.pick(TIER_BODY))
	var W0 := W * 0.94; var D0 := D * 0.92
	var W1 := W * 0.94 * 0.55; var D1 := D * 0.92 * 0.66
	for k in tiers:
		var f0 := float(k) / tiers; var f1 := float(k + 1) / tiers
		var wb := lerpf(W0, W1, f0); var db := lerpf(D0, D1, f0)
		var wt2 := lerpf(W0, W1, f1); var dt2 := lerpf(D0, D1, f1)
		var cor := Rng.hex_lin(r.pick(["#f3efe6", "#e8c766", "#c92a2a", "#2b6cb0"]))
		_box(P.call(0, y + 0.16, 0), Vector3(wb * 0.5 + 0.4, 0.16, db * 0.5 + 0.4), rot, cor, GM.STUCCO, 0.8)
		_frustum(c + Vector3.UP * (y + 0.32), t, n, wb * 0.5, db * 0.5, wt2 * 0.5 + 0.2, dt2 * 0.5 + 0.2, tier_h - 0.32, body * r.range_f(0.92, 1.05))
		# figures in bays on the recessed wall (all four faces), then the parapet of shrines on top
		var bays := maxi(4, int(wb / 0.95))
		for face in [-1.0, 1.0]:
			for i in bays:
				var u := -wb * 0.5 + (i + 0.5) * wb / bays
				var lean := lerpf(db, dt2, 0.3) * 0.5 + 0.08
				if i == bays / 2: continue
				_figure(P.call(u * 0.97, y + 0.38, face * lean), t, n * face, tier_h * 0.55)
			# central window (dark) with a projecting balcony frame
			_box(P.call(0, y + tier_h * 0.45, face * (lerpf(db, dt2, 0.45) * 0.5 + 0.05)), Vector3(minf(1.0, wb * 0.06), tier_h * 0.28, 0.05), rot, Color(0.04, 0.03, 0.03), GM.PAINT, 0.9)
			var pb := maxi(3, int(wt2 / 1.25))
			for i in pb:
				var u := -wt2 * 0.5 + (i + 0.5) * wt2 / pb
				var kind := 0 if (i == 0 or i == pb - 1) else (1 if i == pb / 2 else 2)
				_shrine(P.call(u, y + tier_h, face * (dt2 * 0.5 + 0.12)), t, n * face, rot, tier_h * 0.45, wt2 / pb * 0.85, kind)
		for side in [-1.0, 1.0]:
			var nb2 := maxi(2, int(db / 1.0))
			for i in nb2:
				var v := -db * 0.5 + (i + 0.5) * db / nb2
				_figure(P.call(side * (lerpf(wb, wt2, 0.3) * 0.5 + 0.08), y + 0.38, v), n, t * side, tier_h * 0.5)
			_shrine(P.call(side * (wt2 * 0.5 + 0.12), y + tier_h, 0), n, t * side, rot + PI * 0.5, tier_h * 0.45, dt2 * 0.5, 1)
		y += tier_h
	var wt := W1 + 0.6
	var dt := D1
	# ---- crown: barrel-vault shala roof with gable ends, gold kalasams on the ridge
	var rad := dt * 0.5
	var crown_col := Rng.hex_lin(r.pick(["#2b6cb0", "#2f9e44", "#e8c766", "#c92a2a"]))
	var segs := 10
	for i in segs:
		var a0 := PI * float(i) / segs; var a1 := PI * float(i + 1) / segs
		var q0 := Vector3.UP * (sin(a0) * roof_h) + n * (cos(a0) * rad)
		var q1 := Vector3.UP * (sin(a1) * roof_h) + n * (cos(a1) * rad)
		var base := c + Vector3.UP * y
		var nrm := (q0 + q1).normalized()
		mb.quad(base - t * wt * 0.5 + q0, base + t * wt * 0.5 + q0, base + t * wt * 0.5 + q1, base - t * wt * 0.5 + q1, nrm, crown_col * (0.9 + 0.1 * (i % 2)), Vector4(GM.STUCCO, 0.6, 0, 0))
		for sd in [-1.0, 1.0]:
			mb.tri(base + t * sd * wt * 0.5, base + t * sd * wt * 0.5 + q0, base + t * sd * wt * 0.5 + q1, t * sd, crown_col * 0.85, Vector4(GM.STUCCO, 0.6, 0, 0))
	# kirtimukha gable faces (big arched masks) at both ends
	for sd in [-1.0, 1.0]:
		_box(c + Vector3.UP * (y + roof_h * 0.55) + t * sd * (wt * 0.5 + 0.25), Vector3(0.25, roof_h * 0.6, rad * 0.9), rot, Rng.hex_lin("#e8c766"), GM.STUCCO, 0.6)
	var nk := 5 if tiers < 7 else 11
	if tiers <= 3: nk = 3
	var gold := Rng.hex_lin("#d4a017")
	for i in nk:
		var u := -wt * 0.42 + wt * 0.84 * (float(i) / maxf(1.0, nk - 1))
		var kp := c + t * u + Vector3.UP * (y + roof_h)
		mb.cylinder(kp.x, kp.y, kp.z, 0.22, 0.25, 8, gold, Vector4(GM.METAL, 0.25, 0, 0), Vector4.ZERO, false, 0.32)
		mb.cylinder(kp.x, kp.y + 0.25, kp.z, 0.32, 0.35, 8, gold, Vector4(GM.METAL, 0.25, 0, 0), Vector4.ZERO, false, 0.12)
		mb.cylinder(kp.x, kp.y + 0.6, kp.z, 0.12, 0.55, 8, gold, Vector4(GM.METAL, 0.25, 0, 0), Vector4.ZERO, true, 0.02)

## a sculpted deity / guardian figure: pedestal, body, arms, crowned head — painted polychrome
func _figure(base: Vector3, along: Vector3, out: Vector3, h: float) -> void:
	var rot := atan2(out.x, out.z)
	var skin := Rng.hex_lin(r.pick(["#2b6cb0", "#e8b48a", "#2f9e44", "#c46a3a", "#f3efe6", "#7a4a2a"]))
	var cloth := Rng.hex_lin(r.pick(POLY))
	var s := h
	_box(base + Vector3.UP * (s * 0.05), Vector3(s * 0.2, s * 0.05, s * 0.14), rot, Rng.hex_lin("#f3efe6"), GM.STUCCO)
	_box(base + Vector3.UP * (s * 0.32) + out * 0.04, Vector3(s * 0.12, s * 0.22, s * 0.08), rot, cloth, GM.STUCCO, 0.7)
	_box(base + Vector3.UP * (s * 0.62) + out * 0.04, Vector3(s * 0.13, s * 0.1, s * 0.08), rot, skin, GM.STUCCO, 0.7)
	for sd in [-1.0, 1.0]:
		var arm_up := r.next() < 0.5
		_box(base + along * sd * s * 0.2 + Vector3.UP * (s * (0.72 if arm_up else 0.5)) + out * 0.05, Vector3(s * 0.04, s * 0.13, s * 0.04), rot + sd * 0.4, skin, GM.STUCCO, 0.7)
	_box(base + Vector3.UP * (s * 0.79) + out * 0.04, Vector3(s * 0.07, s * 0.07, s * 0.07), rot, skin, GM.STUCCO, 0.7)
	_box(base + Vector3.UP * (s * 0.92) + out * 0.04, Vector3(s * 0.06, s * 0.08, s * 0.06), rot, Rng.hex_lin("#e8c766"), GM.STUCCO, 0.5)  # crown

## battered tier body: bottom half extents (w0, d0) → top (w1, d1), height h, frame t/n at base c
func _frustum(c: Vector3, t: Vector3, n: Vector3, w0: float, d0: float, w1: float, d1: float, h: float, col: Color) -> void:
	var g := Vector4(GM.STUCCO, 0.85, 0, r.next())
	var B := [c - t * w0 - n * d0, c + t * w0 - n * d0, c + t * w0 + n * d0, c - t * w0 + n * d0]
	var up := Vector3.UP * h
	var T := [c + up - t * w1 - n * d1, c + up + t * w1 - n * d1, c + up + t * w1 + n * d1, c + up - t * w1 + n * d1]
	for i in 4:
		var j := (i + 1) % 4
		var a: Vector3 = B[i]; var b: Vector3 = B[j]; var cc: Vector3 = T[j]; var d: Vector3 = T[i]
		var mid := (a + b + cc + d) * 0.25 - c - up * 0.5
		var nrm := (b - a).cross(d - a).normalized()
		if nrm.dot(mid) < 0: nrm = -nrm
		mb.quad(a, b, cc, d, nrm, col, g, Vector4.ZERO, Vector2(0, 0), Vector2(a.distance_to(b), 0), Vector2(a.distance_to(b), h), Vector2(0, h))
	mb.quad(T[0], T[1], T[2], T[3], Vector3.UP, col * 0.9, g)

## parapet shrine: 0 kuta (square, domed), 1 shala (barrel roof, wide), 2 panjara (narrow, apsidal)
func _shrine(base: Vector3, along: Vector3, out: Vector3, rot: float, h: float, w: float, kind: int) -> void:
	var body := Rng.hex_lin(r.pick(["#f3efe6", "#d9e7f2", "#f2c94c"]))
	var roof := Rng.hex_lin(r.pick(["#2b6cb0", "#2f9e44", "#c92a2a", "#e8c766", "#e88aa8"]))
	var ww := w * (0.42 if kind == 1 else (0.3 if kind == 0 else 0.22))
	_box(base + Vector3.UP * (h * 0.32), Vector3(ww, h * 0.32, ww * 0.8), rot, body, GM.STUCCO)
	_box(base + Vector3.UP * (h * 0.32) + out * (ww * 0.8 + 0.01), Vector3(ww * 0.5, h * 0.2, 0.01), rot, Color(0.08, 0.06, 0.05), GM.PAINT)
	if kind == 1:
		var segs := 5
		for i in segs:
			var a0 := PI * float(i) / segs; var a1 := PI * float(i + 1) / segs
			var y0 := h * 0.64
			var q0 := Vector3.UP * (sin(a0) * h * 0.35) + out * (cos(a0) * ww * 0.85)
			var q1 := Vector3.UP * (sin(a1) * h * 0.35) + out * (cos(a1) * ww * 0.85)
			var b0 := base + Vector3.UP * y0
			mb.quad(b0 - along * ww + q0, b0 + along * ww + q0, b0 + along * ww + q1, b0 - along * ww + q1, (q0 + q1).normalized(), roof, Vector4(GM.STUCCO, 0.6, 0, 0))
		for q in 3:
			var kp := base + along * (float(q) - 1.0) * ww * 0.7 + Vector3.UP * (h * 0.99)
			mb.cylinder(kp.x, kp.y, kp.z, 0.07, 0.22, 6, Rng.hex_lin("#d4a017"), Vector4(GM.METAL, 0.3, 0, 0), Vector4.ZERO, true, 0.02)
	else:
		var rr := ww * 0.95
		mb.cylinder(base.x, base.y + h * 0.64, base.z, rr, h * 0.3, 7, roof, Vector4(GM.STUCCO, 0.6, 0, 0), Vector4.ZERO, true, rr * 0.25)
		mb.cylinder(base.x, base.y + h * 0.94, base.z, 0.06, 0.2, 6, Rng.hex_lin("#d4a017"), Vector4(GM.METAL, 0.3, 0, 0), Vector4.ZERO, true, 0.02)

## miniature shrine pavilion (kuta/panjara) with its own little roof
func _niche(base: Vector3, along: Vector3, out: Vector3, rot: float, h: float, w: float) -> void:
	var col := Rng.hex_lin(r.pick(POLY))
	_box(base + Vector3.UP * (h * 0.4) + out * 0.05, Vector3(w * 0.4, h * 0.4, 0.12), rot, Rng.hex_lin("#f3efe6"), GM.STUCCO)
	_box(base + Vector3.UP * (h * 0.4) + out * 0.17, Vector3(w * 0.25, h * 0.28, 0.02), rot, col * 0.5, GM.STUCCO)
	_box(base + Vector3.UP * (h * 0.86) + out * 0.08, Vector3(w * 0.46, h * 0.07, 0.18), rot, col, GM.STUCCO, 0.6)
	_box(base + Vector3.UP * (h * 0.98), Vector3(w * 0.12, h * 0.07, 0.1), rot, Rng.hex_lin("#d4a017"), GM.METAL, 0.3)
	along = along

func _vimana(s: Dictionary) -> void:
	r = Rng.new(int(s.p[0] * 13 + s.p[1] * 7))
	var f := _frame(s)
	var c: Vector3 = f[0]; var t: Vector3 = f[1]; var n: Vector3 = f[2]; var rot: float = f[3]
	var W: float = s.w; var H: float = s.h
	var gold := Rng.hex_lin("#d4a017")
	var hb := H * 0.35
	_box(c + Vector3.UP * hb * 0.5, Vector3(W * 0.5, hb * 0.5, W * 0.5), rot, Rng.hex_lin("#8a8580"), GM.GRANITE, 0.75, true)
	var y := hb
	var tiers := 3
	for k in tiers:
		var wk := W * (1.0 - 0.22 * k)
		var th := H * 0.12
		_box(c + Vector3.UP * (y + 0.15), Vector3(wk * 0.5 + 0.3, 0.15, wk * 0.5 + 0.3), rot, Rng.hex_lin("#f3efe6"), GM.STUCCO)
		_box(c + Vector3.UP * (y + 0.3 + th * 0.5), Vector3(wk * 0.45, th * 0.5, wk * 0.45), rot, gold * 0.95, GM.METAL, 0.35)
		for face in [t, -t, n, -n]:
			for i in 3:
				var u := (float(i) - 1.0) * wk * 0.3
				var side: Vector3 = (face as Vector3).cross(Vector3.UP)
				_figure(c + face * (wk * 0.45 + 0.05) + side * u + Vector3.UP * (y + 0.3), side, face, th * 0.8)
		y += th + 0.3
	# octagonal griva + dome (shikhara) and the single kalasam
	mb.cylinder(c.x, y, c.z, W * 0.28, H * 0.06, 8, gold, Vector4(GM.METAL, 0.3, 0, 0), Vector4.ZERO, false)
	var dome_r := W * 0.33
	var prev_r := dome_r; var prev_y := y + H * 0.06
	for i in range(1, 6):
		var a := PI * 0.5 * float(i) / 5.0
		var rr := dome_r * cos(a); var yy := y + H * 0.06 + dome_r * 0.9 * sin(a)
		mb.cylinder(c.x, prev_y, c.z, prev_r, yy - prev_y, 8, gold, Vector4(GM.METAL, 0.3, 0, 0), Vector4.ZERO, false, maxf(rr, 0.05))
		prev_r = rr; prev_y = yy
	mb.cylinder(c.x, prev_y, c.z, 0.18, 0.9, 8, gold, Vector4(GM.METAL, 0.25, 0, 0), Vector4.ZERO, true, 0.04)
	t = t

## kaavi-and-white striped compound wall around the temple, open at the gopurams
func _compound(s: Dictionary, gates: Array, kaavi: Color) -> void:
	var pts := CityPack.pts2(s.pts)
	var h: float = s.h
	var white := Rng.hex_lin("#f3efe6")
	for i in pts.size():
		var a := pts[i]; var b := pts[(i + 1) % pts.size()]
		var L := a.distance_to(b)
		if L < 0.5: continue
		var t := (b - a) / L
		var nn := Vector3(t.y, 0, -t.x)
		var stripes := maxi(1, int(L / 0.55))
		for k in stripes:
			var p0 := a + t * (L * k / stripes); var p1 := a + t * (L * (k + 1) / stripes)
			var mid := (p0 + p1) * 0.5
			var gated := false
			for g in gates:
				var gc := Vector2(g.p[0], g.p[1])
				if gc.distance_to(mid) < g.w * 0.5 + 0.5: gated = true
			if gated: continue
			var col := kaavi if k % 2 == 0 else white
			var cen := Vector3(mid.x, h * 0.5, mid.y)
			mb.box(cen, Vector3(p0.distance_to(p1) * 0.5, h * 0.5, 0.3), atan2(nn.x, nn.z), col, Vector4(GM.STUCCO, 0.9, 0, 0))
			var a3 := Vector3(p0.x, 0, p0.y); var b3 := Vector3(p1.x, 0, p1.y)
			colliders.append_array([a3, b3, b3 + Vector3.UP * h, a3, b3 + Vector3.UP * h, a3 + Vector3.UP * h])
		# coping with a white-blue band on top
		var mid2 := (a + b) * 0.5
		var open := false
		for g in gates:
			if Geometry2D.get_closest_point_to_segment(Vector2(g.p[0], g.p[1]), a, b).distance_to(Vector2(g.p[0], g.p[1])) < 2.0: open = true
		if not open:
			mb.box(Vector3(mid2.x, h + 0.12, mid2.y), Vector3(L * 0.5, 0.12, 0.38), atan2(nn.x, nn.z), white, Vector4(GM.STUCCO, 0.9, 0, 0))
