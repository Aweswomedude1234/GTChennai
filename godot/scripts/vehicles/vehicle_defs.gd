class_name VehicleDefs
extends RefCounted
## Vehicle definitions (physics tuning + procedural meshes). Fictional makes only (BRIEF §5).
## Placeholder meshes until the Blender vehicle set lands (docs/PLACEHOLDERS.md); proportions follow
## real dimensions: auto 2.63 × 1.30 × 1.70 m, commuter bike 1.95 m long, hatchback 3.7 × 1.65 × 1.5 m.

const GM := BuildingGen.GM

static func gmv(t: int, rough := 0.6, em := 0.0) -> Vector4:
	return Vector4(t, rough, em, 0)

static func _mat() -> Material:
	return Mats.generic()

## extrude a side profile [(z, y), …] (closed polygon) across x with half-width hw(z)
static func prism(mb: MB, prof: PackedVector2Array, hw_front: float, hw_back: float, col: Color, g: Vector4, x_off := 0.0) -> void:
	var zmin := INF; var zmax := -INF
	for p in prof: zmin = minf(zmin, p.x); zmax = maxf(zmax, p.x)
	var hw := func(z: float) -> float: return lerpf(hw_front, hw_back, (z - zmin) / maxf(zmax - zmin, 0.001))
	var tris := Geometry2D.triangulate_polygon(prof)
	for side in [-1.0, 1.0]:
		var pts := PackedVector3Array()
		for p in prof: pts.append(Vector3(x_off + side * hw.call(p.x), p.y, p.x))
		for i in range(0, tris.size(), 3):
			mb.tri(pts[tris[i]], pts[tris[i + 1]], pts[tris[i + 2]], Vector3(side, 0, 0), col, g)
	var n := prof.size()
	var cen := Vector2.ZERO
	for p in prof: cen += p
	cen /= n
	for i in n:
		var a := prof[i]; var b := prof[(i + 1) % n]
		var e := b - a
		var nn := Vector2(e.y, -e.x).normalized()
		if nn.dot((a + b) * 0.5 - cen) < 0: nn = -nn
		var nrm := Vector3(0, nn.y, nn.x)
		var ha: float = hw.call(a.x); var hb: float = hw.call(b.x)
		mb.quad(Vector3(x_off - ha, a.y, a.x), Vector3(x_off + ha, a.y, a.x), Vector3(x_off + hb, b.y, b.x), Vector3(x_off - hb, b.y, b.x), nrm, col, g)

static func wheel_mesh(rim_col := Color(0.55, 0.55, 0.55), r := 0.3, w := 0.18) -> ArrayMesh:
	var mb := MB.new(false)
	var seg := 16
	var tyre := Color(0.035, 0.035, 0.035)
	# tyre tread (cylinder along X) and sidewalls, rim disc and hub
	for i in seg:
		var a0 := float(i) / seg * TAU; var a1 := float(i + 1) / seg * TAU
		var d0 := Vector3(0, cos(a0), sin(a0)); var d1 := Vector3(0, cos(a1), sin(a1))
		mb.quad(d0 * r + Vector3(-w * 0.5, 0, 0), d1 * r + Vector3(-w * 0.5, 0, 0), d1 * r + Vector3(w * 0.5, 0, 0), d0 * r + Vector3(w * 0.5, 0, 0), (d0 + d1).normalized(), tyre, gmv(GM.RUBBER, 0.85))
		for sx in [-1.0, 1.0]:
			var x := Vector3(sx * w * 0.5, 0, 0)
			mb.quad(d0 * r + x, d1 * r + x, d1 * r * 0.62 + x * 0.9, d0 * r * 0.62 + x * 0.9, Vector3(sx, 0, 0), tyre * 1.4, gmv(GM.RUBBER, 0.8))
			mb.tri(x * 0.85, d0 * r * 0.62 + x * 0.9, d1 * r * 0.62 + x * 0.9, Vector3(sx, 0, 0), rim_col, gmv(GM.METAL, 0.4))
	return mb.to_mesh(_mat())

static func headlamp(mb: MB, c: Vector3, r: float, facing: Vector3) -> void:
	mb.tube(c, c + facing * 0.06, r * 1.15, 10, Color(0.1, 0.1, 0.1), gmv(GM.METAL, 0.4))
	mb.tube(c + facing * 0.055, c + facing * 0.065, r, 10, Color(1.0, 0.97, 0.88), gmv(GM.EMISSIVE, 0.2, 1.0))

static func auto_rickshaw(seed: int) -> Dictionary:
	var r := Rng.new(seed)
	var mb := MB.new(false)
	var yellow := Rng.hex_lin(r.pick(["#f2b705", "#f4c20d", "#f0b400", "#e8b10a"]))
	var green := Rng.hex_lin(r.pick(["#1f5e2e", "#173d24", "#111111"]))
	var canvas := Rng.hex_lin(r.pick(["#141414", "#1b1b1b", "#1d2a1e"]))
	var P := gmv(GM.PAINT, 0.35)
	# floor pan + lower body with the green stripe
	mb.box(Vector3(0, 0.36, 0.05), Vector3(0.6, 0.05, 1.05), 0.0, Color(0.15, 0.15, 0.15), gmv(GM.METAL, 0.6))
	prism(mb, PackedVector2Array([Vector2(-1.32, 0.4), Vector2(-1.32, 0.95), Vector2(-1.18, 1.12), Vector2(-0.82, 1.15), Vector2(-0.72, 0.42)]), 0.28, 0.6, yellow, P)
	prism(mb, PackedVector2Array([Vector2(-1.33, 0.4), Vector2(-1.33, 0.52), Vector2(-0.7, 0.52), Vector2(-0.7, 0.4)]), 0.29, 0.61, green, P)
	# windscreen frame + glass, handlebar, headlamp, front mudguard
	mb.beam(Vector3(-0.5, 1.15, -0.82), Vector3(-0.42, 1.62, -0.92), 0.04, 0.04, Color(0.08, 0.08, 0.08), gmv(GM.METAL, 0.5))
	mb.beam(Vector3(0.5, 1.15, -0.82), Vector3(0.42, 1.62, -0.92), 0.04, 0.04, Color(0.08, 0.08, 0.08), gmv(GM.METAL, 0.5))
	mb.quad(Vector3(-0.48, 1.16, -0.83), Vector3(0.48, 1.16, -0.83), Vector3(0.41, 1.6, -0.92), Vector3(-0.41, 1.6, -0.92), Vector3(0, 0.2, -1).normalized(), Color(0.6, 0.65, 0.7), gmv(GM.GLASS, 0.05))
	mb.beam(Vector3(-0.32, 1.2, -0.62), Vector3(0.32, 1.2, -0.62), 0.03, 0.03, Color(0.1, 0.1, 0.1), gmv(GM.METAL, 0.5))
	headlamp(mb, Vector3(0, 0.88, -1.33), 0.085, Vector3(0, 0, -1))
	mb.box(Vector3(0, 0.36, -1.28), Vector3(0.13, 0.06, 0.24), 0.0, yellow * 0.85, P)
	# driver's seat (front bench) and passenger seat with backrest
	mb.box(Vector3(0, 0.72, -0.45), Vector3(0.3, 0.06, 0.2), 0.0, Rng.hex_lin("#3a2418"), gmv(GM.CLOTH, 0.8))
	mb.box(Vector3(0, 0.66, 0.42), Vector3(0.6, 0.08, 0.24), 0.0, Rng.hex_lin(r.pick(["#3a2418", "#5a1a1a", "#1f2a4a"])), gmv(GM.CLOTH, 0.8))
	mb.box(Vector3(0, 0.98, 0.7), Vector3(0.6, 0.25, 0.05), 0.0, Rng.hex_lin("#3a2418"), gmv(GM.CLOTH, 0.8))
	# rear body over the engine: yellow sides, tail lamps
	prism(mb, PackedVector2Array([Vector2(0.62, 0.38), Vector2(0.62, 0.62), Vector2(0.75, 1.12), Vector2(1.28, 1.12), Vector2(1.32, 0.38)]), 0.62, 0.62, yellow, P)
	prism(mb, PackedVector2Array([Vector2(0.6, 0.38), Vector2(0.6, 0.5), Vector2(1.33, 0.5), Vector2(1.33, 0.38)]), 0.63, 0.63, green, P)
	for sx in [-0.48, 0.48]:
		mb.box(Vector3(sx, 0.8, 1.33), Vector3(0.07, 0.05, 0.02), 0.0, Color(0.7, 0.05, 0.03), gmv(GM.EMISSIVE, 0.3, 0.3))
	# rear panel: slogan board (deity sticker / dialogue) as a coloured plate
	mb.box(Vector3(0, 1.0, 1.335), Vector3(0.36, 0.08, 0.01), 0.0, Rng.hex_lin(r.pick(["#c62828", "#1565c0", "#f5f5f5", "#2e7d32"])), gmv(GM.PAINT, 0.4))
	# canvas roof: curved hood from windscreen to rear, side flaps at the back
	var roof := PackedVector2Array()
	for i in 9:
		var t := float(i) / 8.0
		roof.append(Vector2(lerpf(-0.98, 1.32, t), 1.62 + sin(t * PI) * 0.12 - t * 0.12))
	for i in range(8, -1, -1):
		var t := float(i) / 8.0
		roof.append(Vector2(lerpf(-0.98, 1.32, t), 1.58 + sin(t * PI) * 0.12 - t * 0.12))
	prism(mb, roof, 0.56, 0.66, canvas, gmv(GM.TARP, 0.85))
	prism(mb, PackedVector2Array([Vector2(0.85, 1.12), Vector2(0.85, 1.48), Vector2(1.32, 1.48), Vector2(1.32, 1.12)]), 0.665, 0.665, canvas, gmv(GM.TARP, 0.85))
	# roof frame posts
	for p in [Vector3(-0.6, 0.62, 0.15), Vector3(0.6, 0.62, 0.15)]:
		mb.tube(p, p + Vector3(0, 1.0, 0), 0.018, 5, Color(0.08, 0.08, 0.08), gmv(GM.METAL, 0.5))
	# meter on the left of the handlebar (Chennai autos famously ignore it)
	mb.box(Vector3(-0.25, 1.27, -0.6), Vector3(0.07, 0.09, 0.04), 0.0, Color(0.1, 0.1, 0.1), gmv(GM.METAL, 0.5))
	return {
		"kind": "auto", "name": "Bajrang RE (auto)", "mass": 380.0, "com": Vector3(0, 0.62, 0.22),
		"hull_size": Vector3(1.28, 1.25, 2.6), "hull_pos": Vector3(0, 1.0, 0.0),
		"wheels": [{"p": Vector3(0, 0.41, -1.0), "r": 0.21, "steer": true}, {"p": Vector3(-0.56, 0.41, 0.95), "r": 0.21, "drive": true}, {"p": Vector3(0.56, 0.41, 0.95), "r": 0.21, "drive": true}],
		"susp_rest": 0.32, "susp_k": 9000.0, "susp_c": 650.0, "max_steer": 0.6, "steer_speed": 2.5,
		"engine": 760.0, "top_speed": 15.5, "brake": 0.75, "grip": 1.05, "lat_stiff": 5.0, "roll_res": 1.4, "drag": 0.55,
		"mesh": mb.to_mesh(_mat()), "wheel_mesh": wheel_mesh(Color(0.6, 0.6, 0.6), 0.3, 0.12),
		"cam_height": 1.9, "cam_dist": 5.2, "head": Vector3(0, 1.35, -0.45), "ang_damp": 0.8,
	}

static func bike(seed: int) -> Dictionary:
	var r := Rng.new(seed)
	var mb := MB.new(false)
	var paint := Rng.hex_lin(r.pick(["#151515", "#8a1010", "#1a3a8a", "#5a5a5a", "#0d0d0d", "#3a0a0a", "#c7c7c7"]))
	var P := gmv(GM.PAINT, 0.3)
	var black := Color(0.04, 0.04, 0.04)
	var chrome := Color(0.75, 0.75, 0.75)
	# frame, tank, seat, side panels, engine, exhaust, mudguards, handlebar, headlamp
	mb.beam(Vector3(0, 0.95, -0.55), Vector3(0, 0.55, 0.05), 0.07, 0.07, black, gmv(GM.METAL, 0.5))
	prism(mb, PackedVector2Array([Vector2(-0.52, 0.86), Vector2(-0.45, 1.02), Vector2(-0.12, 1.04), Vector2(0.0, 0.9), Vector2(-0.4, 0.82)]), 0.12, 0.15, paint, P)
	prism(mb, PackedVector2Array([Vector2(-0.05, 0.88), Vector2(-0.02, 0.95), Vector2(0.55, 0.92), Vector2(0.6, 0.86)]), 0.13, 0.12, black, gmv(GM.CLOTH, 0.7))
	prism(mb, PackedVector2Array([Vector2(0.05, 0.62), Vector2(0.05, 0.86), Vector2(0.45, 0.86), Vector2(0.38, 0.62)]), 0.1, 0.1, paint, P)
	mb.box(Vector3(0, 0.45, -0.12), Vector3(0.12, 0.13, 0.17), 0.0, Color(0.25, 0.25, 0.25), gmv(GM.METAL, 0.5))
	mb.tube(Vector3(0.12, 0.38, -0.05), Vector3(0.15, 0.48, 0.72), 0.04, 8, chrome * 0.8, gmv(GM.METAL, 0.25))
	mb.beam(Vector3(0, 0.62, 0.62), Vector3(0, 0.66, 0.95), 0.14, 0.02, black, gmv(GM.PAINT, 0.5))
	mb.beam(Vector3(0, 0.68, -0.7), Vector3(0, 0.62, -0.92), 0.12, 0.02, paint, P)
	mb.tube(Vector3(0, 0.3, -0.62), Vector3(0, 1.0, -0.5), 0.025, 6, chrome, gmv(GM.METAL, 0.25))
	mb.beam(Vector3(-0.36, 1.1, -0.45), Vector3(0.36, 1.1, -0.45), 0.025, 0.025, chrome, gmv(GM.METAL, 0.3))
	headlamp(mb, Vector3(0, 1.0, -0.62), 0.08, Vector3(0, 0, -1))
	mb.box(Vector3(0, 0.82, 0.98), Vector3(0.08, 0.04, 0.03), 0.0, Color(0.7, 0.05, 0.03), gmv(GM.EMISSIVE, 0.3, 0.3))
	mb.box(Vector3(0, 0.72, 0.99), Vector3(0.1, 0.05, 0.005), 0.0, Rng.hex_lin("#f2f2f2"), gmv(GM.PAINT, 0.4))  # number plate
	return {
		"kind": "bike", "name": "Vikram 110 (bike)", "mass": 190.0, "com": Vector3(0, 0.62, 0.05),
		"hull_size": Vector3(0.5, 0.8, 1.9), "hull_pos": Vector3(0, 0.75, 0.0),
		"wheels": [{"p": Vector3(0, 0.47, -0.66), "r": 0.3, "steer": true}, {"p": Vector3(0, 0.47, 0.6), "r": 0.3, "drive": true}],
		"susp_rest": 0.3, "susp_k": 7000.0, "susp_c": 420.0, "max_steer": 0.5, "steer_speed": 3.0,
		"engine": 950.0, "top_speed": 25.0, "brake": 0.9, "grip": 1.15, "lat_stiff": 6.0, "roll_res": 1.0, "drag": 0.35,
		"lean_kp": 60.0, "lean_kd": 9.0,
		"mesh": mb.to_mesh(_mat()), "wheel_mesh": wheel_mesh(Color(0.7, 0.7, 0.7), 0.3, 0.1),
		"cam_height": 1.8, "cam_dist": 4.2, "head": Vector3(0, 1.55, 0.15), "ang_damp": 1.5,
	}

static func car(seed: int) -> Dictionary:
	var r := Rng.new(seed)
	var mb := MB.new(false)
	var paint := Rng.hex_lin(r.pick(["#f2f2f0", "#c8c8c8", "#8a8a8a", "#7a1414", "#1c3a6a", "#2a2a2a", "#d8d0b8", "#3c5a3a", "#b8b8ba"]))
	var P := gmv(GM.PAINT, 0.25)
	var glass := Color(0.12, 0.15, 0.18)
	# lower body (side profile, -Z forward)
	prism(mb, PackedVector2Array([Vector2(-1.85, 0.32), Vector2(-1.88, 0.62), Vector2(-1.6, 0.86), Vector2(-0.8, 0.9), Vector2(1.55, 0.92), Vector2(1.82, 0.88), Vector2(1.85, 0.32)]), 0.8, 0.82, paint, P)
	# cabin: glass house with pillars
	prism(mb, PackedVector2Array([Vector2(-0.82, 0.9), Vector2(-0.2, 1.42), Vector2(1.2, 1.44), Vector2(1.62, 0.92)]), 0.7, 0.74, glass, gmv(GM.GLASS, 0.05))
	prism(mb, PackedVector2Array([Vector2(-0.22, 1.4), Vector2(-0.2, 1.47), Vector2(1.22, 1.48), Vector2(1.2, 1.41)]), 0.69, 0.73, paint, P)
	for z in [0.45, 1.2]:
		mb.box(Vector3(0, 1.15, z), Vector3(0.745, 0.27, 0.04), 0.0, paint * 0.9, P)
	# bumpers, grille, lamps, plates
	mb.box(Vector3(0, 0.42, -1.86), Vector3(0.8, 0.1, 0.06), 0.0, Color(0.1, 0.1, 0.1), gmv(GM.RUBBER, 0.6))
	mb.box(Vector3(0, 0.42, 1.86), Vector3(0.8, 0.1, 0.06), 0.0, Color(0.1, 0.1, 0.1), gmv(GM.RUBBER, 0.6))
	mb.box(Vector3(0, 0.66, -1.88), Vector3(0.32, 0.07, 0.01), 0.0, Color(0.05, 0.05, 0.05), gmv(GM.METAL, 0.4))
	for sx in [-0.6, 0.6]:
		mb.box(Vector3(sx, 0.74, -1.79), Vector3(0.16, 0.06, 0.06), 0.0, Color(1, 0.97, 0.9), gmv(GM.EMISSIVE, 0.2, 0.6))
		mb.box(Vector3(sx, 0.76, 1.84), Vector3(0.14, 0.07, 0.03), 0.0, Color(0.7, 0.04, 0.03), gmv(GM.EMISSIVE, 0.3, 0.3))
	mb.box(Vector3(0, 0.5, -1.93), Vector3(0.25, 0.06, 0.005), 0.0, Color(0.95, 0.95, 0.95), gmv(GM.PAINT, 0.4))
	mb.box(Vector3(0, 0.62, 1.93), Vector3(0.25, 0.06, 0.005), 0.0, Color(0.95, 0.95, 0.95), gmv(GM.PAINT, 0.4))
	for sx in [-0.86, 0.86]:
		mb.box(Vector3(sx, 1.0, -0.72), Vector3(0.05, 0.05, 0.1), 0.0, paint, P)  # mirrors
	return {
		"kind": "car", "name": "Mithra Swift-ish (hatchback)", "mass": 980.0, "com": Vector3(0, 0.5, -0.1),
		"hull_size": Vector3(1.64, 1.1, 3.72), "hull_pos": Vector3(0, 0.9, 0.0),
		"wheels": [{"p": Vector3(-0.72, 0.53, -1.22), "r": 0.29, "steer": true, "drive": true}, {"p": Vector3(0.72, 0.53, -1.22), "r": 0.29, "steer": true, "drive": true},
			{"p": Vector3(-0.72, 0.53, 1.2), "r": 0.29}, {"p": Vector3(0.72, 0.53, 1.2), "r": 0.29}],
		"susp_rest": 0.33, "susp_k": 26000.0, "susp_c": 2400.0, "max_steer": 0.55, "steer_speed": 2.2,
		"engine": 4200.0, "top_speed": 42.0, "brake": 0.95, "grip": 1.1, "lat_stiff": 5.0, "roll_res": 1.2, "drag": 0.42,
		"mesh": mb.to_mesh(_mat()), "wheel_mesh": wheel_mesh(Color(0.6, 0.6, 0.62), 0.3, 0.2),
		"cam_height": 2.2, "cam_dist": 6.4, "head": Vector3(-0.35, 1.22, -0.1), "exit_left": false, "ang_damp": 0.5,
	}
