class_name Props
extends RefCounted
## Shared prop meshes (built once, used through MultiMeshInstance3D per chunk): trees and palms,
## electricity poles, street lamps, transformers, parked two-wheelers, shop-front clutter.
## Proportions follow STYLE_BIBLE §4 and street measurements (pole 8.5–9 m, lamps 7–9 m).

const GM := BuildingGen.GM
static var _m := {}
static var _foliage: ShaderMaterial
static var _mutex := Mutex.new()

static func g(t: int, rough := 0.7, em := 0.0) -> Vector4:
	return Vector4(t, rough, em, 0)

static func foliage_mat() -> ShaderMaterial:
	if _foliage == null:
		_foliage = ShaderMaterial.new()
		_foliage.shader = load("res://shaders/foliage.gdshader")
		_foliage.set_shader_parameter("leaves", load("res://textures/leaves_c.png"))
		_foliage.set_shader_parameter("frond", load("res://textures/frond_c.png"))
	return _foliage

static func get_mesh(name: String) -> Mesh:
	_mutex.lock()
	if not _m.has(name):
		_m[name] = _build(name)
	var m: Mesh = _m[name]
	_mutex.unlock()
	return m

static func _build(name: String) -> Mesh:
	match name:
		"tree_rain": return _tree(11, 4.6, 7.2, 2.6, 0.38, Color(0.85, 0.95, 0.75), 130)
		"tree_neem": return _tree(23, 3.0, 5.4, 2.2, 0.26, Color(0.95, 1.0, 0.85), 80)
		"tree_gulmohar": return _tree(37, 4.0, 5.8, 1.8, 0.3, Color(1.0, 0.95, 0.8), 100)
		"tree_young": return _tree(41, 1.6, 3.4, 1.3, 0.12, Color(1.0, 1.05, 0.9), 34)
		"palm": return _palm(5, 9.5)
		"palm_short": return _palm(9, 6.5)
		"shrub": return _shrub(3)
		"pole": return _pole(false)
		"pole_lamp": return _pole(true)
		"lamp_post": return _lamp_post()
		"transformer": return _transformer()
		"bike_parked": return VehicleModel.baked("bike", 1, true)
		"scooter_parked": return VehicleModel.baked("scooter", 0, true)
		"crate": return _crate()
		"stool": return _stool()
		"cylinder": return _gas_cylinder()
		"drum": return _drum()
		"sack": return _sack()
		"bin": return _bin()
		"stand": return _display_stand()
		"cart": return _cart()
		"boat": return _boat()
		"marina_lamp": return _marina_lamp()
		"umbrella": return _umbrella()
		"fruit_cart": return _fruit_cart(7)
		"flower_mat": return _flower_mat(11)
		"coconuts": return _coconuts(13)
		"hoarding": return _hoarding()
	push_error("unknown prop " + name)
	return BoxMesh.new()

static func _surface(mesh: ArrayMesh, mb: MB, mat: Material) -> void:
	if mb.count() > 0: mb.add_to(mesh, mat)

## broad-leaf tree: trunk + main branches (bark) and a canopy of leaf cards in a flattened ellipsoid
static func _tree(seed: int, rad: float, crown_y: float, crown_h: float, trunk_r: float, tint: Color, cards: int) -> ArrayMesh:
	var r := Rng.new(seed)
	var bark := MB.new(false); var leaf := MB.new(false)
	var bark_col := Rng.hex_lin("#5a4a3c")
	var top := Vector3(r.range_f(-0.3, 0.3), crown_y - crown_h * 0.45, r.range_f(-0.3, 0.3))
	bark.tube(Vector3.ZERO, top, trunk_r, 8, bark_col, g(GM.WOOD, 0.9), Vector4.ZERO, trunk_r * 0.7)
	# whitewashed / kaavi base band on street trees (painted against cattle and for visibility)
	if seed % 2 == 1: bark.tube(Vector3(0, 0.0, 0), Vector3(0, 1.1, 0), trunk_r * 1.05, 8, Rng.hex_lin("#e9e4d8"), g(GM.STUCCO, 0.9))
	var nb := 4 + int(r.next() * 3)
	var tips: Array[Vector3] = []
	for i in nb:
		var a := r.next() * TAU
		var tip := top + Vector3(cos(a) * rad * r.range_f(0.4, 0.75), crown_h * r.range_f(0.2, 0.6), sin(a) * rad * r.range_f(0.4, 0.75))
		bark.tube(top, tip, trunk_r * 0.45, 6, bark_col, g(GM.WOOD, 0.9), Vector4.ZERO, trunk_r * 0.15)
		tips.append(tip)
	for i in cards:
		# points in a flattened ellipsoid, denser near branch tips
		var c: Vector3
		if r.next() < 0.6:
			var tp: Vector3 = tips[int(r.next() * tips.size()) % tips.size()]
			c = tp + Vector3(r.range_f(-1, 1), r.range_f(-0.6, 0.8), r.range_f(-1, 1)) * rad * 0.45
		else:
			var u := Vector3(r.range_f(-1, 1), r.range_f(-1, 1), r.range_f(-1, 1))
			if u.length() > 1.0: u = u.normalized()
			c = Vector3(0, crown_y, 0) + Vector3(u.x * rad, u.y * crown_h * 0.6, u.z * rad)
		var s := r.range_f(1.3, 2.1)
		var nrm := (c - Vector3(0, crown_y - crown_h * 0.3, 0)).normalized()
		var tang := nrm.cross(Vector3.UP if absf(nrm.y) < 0.9 else Vector3.RIGHT).normalized().rotated(nrm, r.next() * TAU)
		var bit := nrm.cross(tang)
		var col := tint * r.range_f(0.8, 1.15)
		var a0 := c - tang * s * 0.5 - bit * s * 0.5
		leaf.quad(a0, a0 + tang * s, a0 + tang * s + bit * s, a0 + bit * s, nrm, col, Vector4(0, 1.0, 0, 0), Vector4.ZERO, Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0))
	var mesh := ArrayMesh.new()
	_surface(mesh, bark, Mats.generic())
	_surface(mesh, leaf, foliage_mat())
	return mesh

static func _palm(seed: int, h: float) -> ArrayMesh:
	var r := Rng.new(seed)
	var bark := MB.new(false); var leaf := MB.new(false)
	var bend := Vector3(r.range_f(-1, 1), 0, r.range_f(-1, 1)).normalized() * h * 0.12
	var prev := Vector3.ZERO
	var segs := 8
	for i in range(1, segs + 1):
		var t := float(i) / segs
		var p := Vector3(0, h * t, 0) + bend * t * t
		bark.tube(prev, p, lerpf(0.22, 0.15, t), 7, Rng.hex_lin("#7a6e60") * (0.9 + 0.1 * float(i % 2)), g(GM.WOOD, 0.95), Vector4.ZERO, lerpf(0.22, 0.15, t + 1.0 / segs))
		prev = p
	var crown := prev
	for q in 5:  # coconuts
		var a := q * TAU / 5.0
		bark.cylinder(crown.x + cos(a) * 0.25, crown.y - 0.55, crown.z + sin(a) * 0.25, 0.13, 0.22, 6, Rng.hex_lin("#6b7a2a" if q % 2 == 0 else "#8a6a2a"), g(GM.PAINT, 0.6))
	var nf := 16
	for i in nf:
		var a := float(i) / nf * TAU + r.next() * 0.3
		var up := r.range_f(-0.15, 0.55) if i % 2 == 0 else r.range_f(-0.5, 0.2)
		var dir := Vector3(cos(a), up, sin(a)).normalized()
		var L := r.range_f(3.6, 4.8)
		var side := Vector3(-sin(a), 0, cos(a))
		# two-segment drooping frond
		var mid := crown + dir * L * 0.5 + Vector3(0, 0.15, 0)
		var tip := crown + dir * L + Vector3(0, -L * 0.35, 0)
		var w := 0.7
		var col := Color(1, 1, 1) * r.range_f(0.85, 1.1)
		var n1 := (mid - crown).cross(side).normalized()
		if n1.y < 0: n1 = -n1
		leaf.quad(crown - side * w * 0.3, crown + side * w * 0.3, mid + side * w, mid - side * w, n1, col, Vector4(1, 0.7, 0, 0), Vector4.ZERO, Vector2(0, 0), Vector2(1, 0), Vector2(1, 0.5), Vector2(0, 0.5))
		var n2 := (tip - mid).cross(side).normalized()
		if n2.y < 0: n2 = -n2
		leaf.quad(mid - side * w, mid + side * w, tip + side * w * 0.3, tip - side * w * 0.3, n2, col, Vector4(1, 1.0, 0, 0), Vector4.ZERO, Vector2(0, 0.5), Vector2(1, 0.5), Vector2(1, 1), Vector2(0, 1))
	var mesh := ArrayMesh.new()
	_surface(mesh, bark, Mats.generic())
	_surface(mesh, leaf, foliage_mat())
	return mesh

static func _shrub(seed: int) -> ArrayMesh:
	var r := Rng.new(seed)
	var leaf := MB.new(false)
	for i in 18:
		var c := Vector3(r.range_f(-0.6, 0.6), r.range_f(0.3, 1.1), r.range_f(-0.6, 0.6))
		var nrm := Vector3(c.x, 0.6, c.z).normalized()
		var tang := nrm.cross(Vector3.UP).normalized().rotated(nrm, r.next() * TAU)
		var bit := nrm.cross(tang)
		var s := 0.9
		var a0 := c - tang * s * 0.5 - bit * s * 0.5
		leaf.quad(a0, a0 + tang * s, a0 + tang * s + bit * s, a0 + bit * s, nrm, Color(0.9, 1.05, 0.85), Vector4(0, 0.3, 0, 0), Vector4.ZERO, Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0))
	var mesh := ArrayMesh.new()
	_surface(mesh, leaf, foliage_mat())
	return mesh

## Chennai concrete electricity pole (PSC, I-section) with crossarm and insulators; optional LED arm
static func _pole(lamp: bool) -> ArrayMesh:
	var mb := MB.new(false)
	var conc := Rng.hex_lin("#9a968c")
	mb.box(Vector3(0, 4.3, 0), Vector3(0.11, 4.3, 0.07), 0.0, conc, g(GM.CONCRETE, 0.9))
	mb.box(Vector3(0, 8.45, 0), Vector3(0.75, 0.05, 0.05), 0.0, Rng.hex_lin("#3a3a3a"), g(GM.RUST, 0.7))  # MS crossarm
	for x in [-0.65, 0.0, 0.65]:
		mb.cylinder(x, 8.5, 0, 0.045, 0.14, 6, Rng.hex_lin("#d9d2c4"), g(GM.PAINT, 0.4))  # porcelain insulators
	mb.box(Vector3(0, 2.6, 0.1), Vector3(0.16, 0.22, 0.06), 0.0, Rng.hex_lin("#5a5a58"), g(GM.METAL, 0.6))  # junction box
	mb.box(Vector3(0, 1.0, 0.0), Vector3(0.115, 1.0, 0.075), 0.0, Rng.hex_lin("#e8e2d0"), g(GM.STUCCO, 0.9)) # whitewash band
	if lamp:
		mb.tube(Vector3(0, 7.2, 0), Vector3(0, 7.6, -1.4), 0.03, 5, Rng.hex_lin("#6a6a68"), g(GM.METAL, 0.5))
		mb.box(Vector3(0, 7.58, -1.55), Vector3(0.14, 0.05, 0.28), 0.0, Rng.hex_lin("#5a5a5a"), g(GM.METAL, 0.4))
		mb.box(Vector3(0, 7.52, -1.55), Vector3(0.12, 0.012, 0.24), 0.0, Color(0.95, 0.97, 1.0), g(GM.LED, 0.3, 1.0))
	return mb.to_mesh(Mats.generic())

## tall steel lamp post with a sodium head (main roads, Marina has 12 m four-head posts)
static func _lamp_post() -> ArrayMesh:
	var mb := MB.new(false)
	var steel := Rng.hex_lin("#7a7e80")
	mb.tube(Vector3.ZERO, Vector3(0, 8.5, 0), 0.09, 8, steel, g(GM.METAL, 0.5), Vector4.ZERO, 0.05)
	mb.tube(Vector3(0, 8.3, 0), Vector3(0, 8.9, -1.8), 0.04, 6, steel, g(GM.METAL, 0.5))
	mb.box(Vector3(0, 8.85, -2.0), Vector3(0.18, 0.08, 0.38), 0.0, Rng.hex_lin("#4a4a4a"), g(GM.METAL, 0.4))
	mb.box(Vector3(0, 8.76, -2.0), Vector3(0.15, 0.015, 0.32), 0.0, Color(1.0, 0.8, 0.5), g(GM.SODIUM, 0.3, 1.0))
	mb.cylinder(0, 0, 0, 0.18, 0.5, 8, Rng.hex_lin("#8a8a86"), g(GM.CONCRETE, 0.9))
	return mb.to_mesh(Mats.generic())

static func _transformer() -> ArrayMesh:
	var mb := MB.new(false)
	var grey := Rng.hex_lin("#7d8a84")
	for x in [-1.0, 1.0]:
		mb.box(Vector3(x, 4.3, 0), Vector3(0.11, 4.3, 0.07), 0.0, Rng.hex_lin("#9a968c"), g(GM.CONCRETE, 0.9))
	mb.box(Vector3(0, 2.6, 0), Vector3(1.1, 0.06, 0.4), 0.0, Rng.hex_lin("#3a3a3a"), g(GM.RUST, 0.7))  # platform
	mb.box(Vector3(0, 3.25, 0), Vector3(0.55, 0.6, 0.35), 0.0, grey, g(GM.METAL, 0.6))
	for i in 5:
		mb.box(Vector3(-0.5 + i * 0.25, 3.2, 0.37), Vector3(0.05, 0.5, 0.03), 0.0, grey * 0.9, g(GM.METAL, 0.6))  # radiator fins
	for x in [-0.3, 0.0, 0.3]:
		mb.cylinder(x, 3.85, 0, 0.05, 0.35, 6, Rng.hex_lin("#8a4a2a"), g(GM.PAINT, 0.4))  # bushings
	mb.box(Vector3(0, 1.0, 0.5), Vector3(0.5, 1.0, 0.04), 0.0, Rng.hex_lin("#5a5a58"), g(GM.RUST, 0.7))  # mesh fence front
	mb.box(Vector3(0, 1.7, 0.53), Vector3(0.2, 0.15, 0.01), 0.0, Rng.hex_lin("#c62828"), g(GM.PAINT, 0.5))  # danger board
	return mb.to_mesh(Mats.generic())

static func _parked_bike(seed: int) -> ArrayMesh:
	var d := VehicleDefs.bike(seed)
	var mesh: ArrayMesh = d.mesh.duplicate()
	var mb := MB.new(false)
	for w in d.wheels:
		var wm: ArrayMesh = d.wheel_mesh
		var arr := wm.surface_get_arrays(0)
		var base := mb.count()
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var nrms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR]
		var c0: PackedFloat32Array = arr[Mesh.ARRAY_CUSTOM0]
		for i in verts.size():
			mb.vert(verts[i] + Vector3(w.p.x, w.r, w.p.z), nrms[i], cols[i], Vector2.ZERO, Vector4(c0[i * 4], c0[i * 4 + 1], c0[i * 4 + 2], c0[i * 4 + 3]))
		for i in arr[Mesh.ARRAY_INDEX]: mb.idx.append(i + base)
	# side stand lean is applied by the instance transform
	mb.add_to(mesh, Mats.generic())
	return mesh

static func _parked_scooter(seed: int) -> ArrayMesh:
	var mb := MB.new(false)
	var r := Rng.new(seed)
	var P := g(GM.PAINT, 0.3)
	var paint := Color(1, 1, 1)  # tinted per instance
	VehicleDefs.prism(mb, PackedVector2Array([Vector2(-0.62, 0.35), Vector2(-0.6, 1.0), Vector2(-0.45, 1.05), Vector2(-0.38, 0.45), Vector2(0.15, 0.4), Vector2(0.2, 0.72), Vector2(0.7, 0.82), Vector2(0.75, 0.35)]), 0.18, 0.2, paint, P)
	VehicleDefs.prism(mb, PackedVector2Array([Vector2(0.05, 0.78), Vector2(0.08, 0.86), Vector2(0.65, 0.88), Vector2(0.7, 0.8)]), 0.15, 0.14, Color(0.05, 0.05, 0.05), g(GM.CLOTH, 0.7))
	mb.beam(Vector3(-0.3, 1.12, -0.55), Vector3(0.3, 1.12, -0.55), 0.03, 0.03, Color(0.15, 0.15, 0.15), g(GM.METAL, 0.4))
	for z in [-0.58, 0.55]:
		var wm := VehicleDefs.wheel_mesh(Color(0.6, 0.6, 0.6), 0.22, 0.1)
		var arr := wm.surface_get_arrays(0)
		var base := mb.count()
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var nrms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR]
		var c0: PackedFloat32Array = arr[Mesh.ARRAY_CUSTOM0]
		for i in verts.size():
			mb.vert(verts[i] + Vector3(0, 0.22, z), nrms[i], cols[i], Vector2.ZERO, Vector4(c0[i * 4], c0[i * 4 + 1], c0[i * 4 + 2], c0[i * 4 + 3]))
		for i in arr[Mesh.ARRAY_INDEX]: mb.idx.append(i + base)
	r.next()
	return mb.to_mesh(Mats.generic())

static func _crate() -> ArrayMesh:
	var mb := MB.new(false)
	var c := Color(1, 1, 1)  # tinted red/blue per instance
	mb.box(Vector3(0, 0.15, 0), Vector3(0.25, 0.15, 0.18), 0.0, c, g(GM.PAINT, 0.5))
	mb.box(Vector3(0, 0.31, 0), Vector3(0.22, 0.01, 0.15), 0.0, Rng.hex_lin("#e0c070"), g(GM.CLOTH, 0.9))  # produce on top
	return mb.to_mesh(Mats.generic())

static func _stool() -> ArrayMesh:
	var mb := MB.new(false)
	var c := Color(1, 1, 1)
	mb.cylinder(0, 0.0, 0, 0.17, 0.42, 10, c, g(GM.PAINT, 0.4), Vector4.ZERO, true, 0.14)
	return mb.to_mesh(Mats.generic())

static func _gas_cylinder() -> ArrayMesh:
	var mb := MB.new(false)
	mb.cylinder(0, 0, 0, 0.16, 0.62, 10, Rng.hex_lin("#b71c1c"), g(GM.PAINT, 0.4))
	mb.tube(Vector3(0, 0.62, 0), Vector3(0, 0.72, 0), 0.05, 6, Rng.hex_lin("#b71c1c"), g(GM.PAINT, 0.4))
	return mb.to_mesh(Mats.generic())

static func _drum() -> ArrayMesh:
	var mb := MB.new(false)
	mb.cylinder(0, 0, 0, 0.29, 0.88, 12, Color(1, 1, 1), g(GM.TANK, 0.5))
	return mb.to_mesh(Mats.generic())

static func _sack() -> ArrayMesh:
	var mb := MB.new(false)
	mb.cylinder(0, 0, 0, 0.24, 0.55, 8, Rng.hex_lin("#d8cfb8"), g(GM.CLOTH, 0.95), Vector4.ZERO, true, 0.18)
	return mb.to_mesh(Mats.generic())

static func _bin() -> ArrayMesh:
	var mb := MB.new(false)
	mb.box(Vector3(0, 0.55, 0), Vector3(0.6, 0.55, 0.45), 0.0, Rng.hex_lin("#2e6b3a"), g(GM.RUST, 0.7))
	mb.box(Vector3(0, 1.12, 0), Vector3(0.62, 0.04, 0.47), 0.0, Rng.hex_lin("#244f2c"), g(GM.METAL, 0.6))
	for i in 6:  # overflowing garbage
		mb.box(Vector3(-0.5 + i * 0.2, 0.08, 0.6), Vector3(0.15, 0.08, 0.18), i * 0.7, Rng.hex_lin(["#d8d0c0", "#2a5a2a", "#c03030", "#202020", "#e0e0e0", "#8a6a3a"][i]), g(GM.CLOTH, 0.9))
	return mb.to_mesh(Mats.generic())

static func _display_stand() -> ArrayMesh:
	var mb := MB.new(false)
	var w := Rng.hex_lin("#6a4a30")
	for x in [-0.5, 0.5]:
		mb.box(Vector3(x, 0.55, 0), Vector3(0.025, 0.55, 0.3), 0.0, w, g(GM.WOOD, 0.8))
	for i in 3:
		var y := 0.3 + i * 0.32
		mb.box(Vector3(0, y, -0.05 + i * 0.07), Vector3(0.52, 0.02, 0.18), 0.0, w, g(GM.WOOD, 0.8))
		mb.box(Vector3(0, y + 0.08, -0.05 + i * 0.07), Vector3(0.48, 0.06, 0.15), 0.0, Color(1, 1, 1), g(GM.CLOTH, 0.8))  # goods (tinted)
	return mb.to_mesh(Mats.generic())


## sundal / bajji / ice-cream pushcart: wooden box on four cycle wheels, glass case, tarpaulin canopy,
## tube light, steel vessels; body tinted per instance
static func _cart() -> ArrayMesh:
	var mb := MB.new(false)
	var wood := Rng.hex_lin("#6a4a30")
	mb.box(Vector3(0, 0.82, 0), Vector3(0.75, 0.22, 0.45), 0.0, Color(1, 1, 1), g(GM.PAINT, 0.5))
	mb.box(Vector3(0, 0.58, 0), Vector3(0.77, 0.03, 0.47), 0.0, wood, g(GM.WOOD, 0.8))
	mb.box(Vector3(0, 1.2, -0.1), Vector3(0.6, 0.16, 0.25), 0.0, Color(0.7, 0.8, 0.85), g(GM.GLASS, 0.05))
	for x in [-0.55, 0.55]:
		for z in [-0.4, 0.4]:
			mb.tube(Vector3(x, 1.04, z), Vector3(x, 2.2, z), 0.02, 4, Rng.hex_lin("#5a5a5a"), g(GM.METAL, 0.5))
	mb.box(Vector3(0, 2.22, 0), Vector3(0.85, 0.02, 0.6), 0.0, Rng.hex_lin("#1565c0"), g(GM.TARP, 0.7))
	mb.box(Vector3(0, 2.1, -0.4), Vector3(0.5, 0.02, 0.02), 0.0, Color(0.95, 0.97, 1.0), g(GM.EMISSIVE, 0.3, 1.0))
	for q in 3:
		mb.cylinder(-0.4 + q * 0.4, 1.04, 0.2, 0.15, 0.22, 10, Rng.hex_lin("#c9c9c6"), g(GM.METAL, 0.25))  # steel vessels
	mb.cylinder(0.4, 1.26, 0.2, 0.11, 0.05, 10, Rng.hex_lin("#e0b030"), g(GM.CLOTH, 0.9))  # sundal heap
	mb.box(Vector3(0, 1.5, 0.46), Vector3(0.6, 0.12, 0.01), 0.0, Rng.hex_lin("#f9a825"), g(GM.PAINT, 0.4))  # name board
	for x in [-0.6, 0.6]:
		for z in [-0.35, 0.35]:
			var wm := VehicleDefs.wheel_mesh(Color(0.5, 0.5, 0.5), 0.28, 0.04)
			var arr := wm.surface_get_arrays(0)
			var base := mb.count()
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var nrms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR]
			var c0: PackedFloat32Array = arr[Mesh.ARRAY_CUSTOM0]
			for i in verts.size():
				mb.vert(verts[i] * Vector3(1, 1, 1) + Vector3(x, 0.28, z), nrms[i], cols[i], Vector2.ZERO, Vector4(c0[i * 4], c0[i * 4 + 1], c0[i * 4 + 2], c0[i * 4 + 3]))
			for i in arr[Mesh.ARRAY_INDEX]: mb.idx.append(i + base)
	return mb.to_mesh(Mats.generic())

## fibre-glass fishing boat (vallam) drawn up on the sand, hull tinted per instance, white sheer stripe
static func _boat() -> ArrayMesh:
	var mb := MB.new(false)
	var L := 8.5; var W := 1.6
	var segs := 10
	for i in segs:
		var t0 := float(i) / segs; var t1 := float(i + 1) / segs
		var w0 := W * 0.5 * sin(PI * clampf(t0 * 1.05, 0.0, 1.0)) + 0.05; var w1 := W * 0.5 * sin(PI * clampf(t1 * 1.05, 0.0, 1.0)) + 0.05
		var z0 := -L * 0.5 + L * t0; var z1 := -L * 0.5 + L * t1
		var h0 := 0.75 + 0.35 * absf(t0 - 0.5) * 2.0; var h1 := 0.75 + 0.35 * absf(t1 - 0.5) * 2.0
		for sd in [-1.0, 1.0]:
			mb.quad(Vector3(sd * w0 * 0.55, 0.1, z0), Vector3(sd * w1 * 0.55, 0.1, z1), Vector3(sd * w1, h1, z1), Vector3(sd * w0, h0, z0), Vector3(sd, -0.3, 0).normalized(), Color(1, 1, 1), g(GM.PAINT, 0.35))
			mb.quad(Vector3(sd * w0, h0 - 0.12, z0), Vector3(sd * w1, h1 - 0.12, z1), Vector3(sd * w1, h1, z1), Vector3(sd * w0, h0, z0), Vector3(sd, 0, 0), Color(0.95, 0.95, 0.92), g(GM.PAINT, 0.35))
		mb.quad(Vector3(-w0 * 0.55, 0.1, z0), Vector3(w0 * 0.55, 0.1, z0), Vector3(w1 * 0.55, 0.1, z1), Vector3(-w1 * 0.55, 0.1, z1), Vector3.UP, Rng.hex_lin("#5a4a3a"), g(GM.WOOD, 0.8))
	mb.box(Vector3(0, 0.5, 0), Vector3(W * 0.45, 0.04, 0.12), 0.0, Rng.hex_lin("#6a4a30"), g(GM.WOOD, 0.8))
	mb.box(Vector3(0, 0.75, L * 0.5 - 0.6), Vector3(0.18, 0.35, 0.2), 0.0, Rng.hex_lin("#2a2a2a"), g(GM.METAL, 0.5))  # outboard
	mb.box(Vector3(0.3, 0.3, -1.0), Vector3(0.6, 0.12, 0.8), 0.3, Rng.hex_lin("#3a5a7a"), g(GM.CLOTH, 0.9))  # nets
	return mb.to_mesh(Mats.generic())

## Marina promenade light: 12 m galvanised pole with four LED heads
static func _marina_lamp() -> ArrayMesh:
	var mb := MB.new(false)
	var steel := Rng.hex_lin("#8a8e90")
	mb.tube(Vector3.ZERO, Vector3(0, 12.0, 0), 0.13, 8, steel, g(GM.METAL, 0.45), Vector4.ZERO, 0.07)
	mb.cylinder(0, 0, 0, 0.3, 0.6, 8, Rng.hex_lin("#8a8a86"), g(GM.CONCRETE, 0.9))
	for q in 4:
		var a := q * PI * 0.5 + PI * 0.25
		var d := Vector3(cos(a), 0, sin(a))
		mb.tube(Vector3(0, 11.7, 0), Vector3(0, 11.9, 0) + d * 0.9, 0.035, 5, steel, g(GM.METAL, 0.45))
		mb.box(Vector3(0, 11.9, 0) + d * 1.05, Vector3(0.22, 0.06, 0.12), -a, Rng.hex_lin("#5a5a5a"), g(GM.METAL, 0.4))
		mb.box(Vector3(0, 11.83, 0) + d * 1.05, Vector3(0.19, 0.012, 0.1), -a, Color(0.95, 0.97, 1.0), g(GM.LED, 0.3, 1.0))
	return mb.to_mesh(Mats.generic())


## big vendor umbrella (the striped beach type every footpath stall uses); panels tint per instance
static func _umbrella() -> ArrayMesh:
	var mb := MB.new(false)
	mb.tube(Vector3(0, 0, 0), Vector3(0, 2.35, 0), 0.02, 5, Rng.hex_lin("#6a6a6a"), g(GM.METAL, 0.5))
	var segs := 10
	var R := 1.25
	for i in segs:
		var a0 := TAU * i / segs; var a1 := TAU * (i + 1) / segs
		var tint := Color(1, 1, 1) if i % 2 == 0 else Rng.hex_lin("#ffe9a0")   # stripes: tint × white / × cream
		var top := Vector3(0, 2.45, 0)
		var e0 := Vector3(cos(a0) * R, 2.05, sin(a0) * R); var e1 := Vector3(cos(a1) * R, 2.05, sin(a1) * R)
		var nrm := (e1 - top).cross(e0 - top).normalized()
		if nrm.y < 0: nrm = -nrm
		mb.tri(top, e0, e1, nrm, tint, g(GM.TARP, 0.8))
		mb.tri(top, e1, e0, -nrm, tint * 0.8, g(GM.TARP, 0.8))
		# scalloped valance
		mb.quad(e0, e1, e1 - Vector3(0, 0.12, 0), e0 - Vector3(0, 0.12, 0), Vector3(cos((a0 + a1) * 0.5), 0, sin((a0 + a1) * 0.5)), tint, g(GM.TARP, 0.8))
	return mb.to_mesh(Mats.generic())

## four-wheel wooden fruit pushcart piled with bananas, oranges, apples and pomegranates
static func _fruit_cart(seed: int) -> ArrayMesh:
	var r := Rng.new(seed)
	var mb := MB.new(false)
	var wood := Rng.hex_lin("#7a5232")
	mb.box(Vector3(0, 0.78, 0), Vector3(0.95, 0.04, 0.6), 0.0, wood, g(GM.WOOD, 0.85))
	for side in [-1.0, 1.0]:
		mb.box(Vector3(0, 0.86, side * 0.6), Vector3(0.95, 0.06, 0.02), 0.0, wood * 0.9, g(GM.WOOD, 0.85))
		mb.box(Vector3(side * 0.95, 0.86, 0), Vector3(0.02, 0.06, 0.6), 0.0, wood * 0.9, g(GM.WOOD, 0.85))
	mb.beam(Vector3(0.95, 0.8, -0.4), Vector3(1.55, 0.95, -0.4), 0.04, 0.04, wood, g(GM.WOOD, 0.8))   # handles
	mb.beam(Vector3(0.95, 0.8, 0.4), Vector3(1.55, 0.95, 0.4), 0.04, 0.04, wood, g(GM.WOOD, 0.8))
	for x in [-0.7, 0.7]:
		for z in [-0.5, 0.5]:
			mb.cylinder(x, 0.0, z, 0.03, 0.78, 5, wood * 0.8, g(GM.WOOD, 0.9))
	# fruit heaps: tiered mounds of balls (oranges / apples / pomegranates / sweet lime)
	var fruits := [[Rng.hex_lin("#f08a10"), 0.045], [Rng.hex_lin("#b0121a"), 0.042], [Rng.hex_lin("#9a1a2a"), 0.05], [Rng.hex_lin("#9cc23a"), 0.045]]
	for k in 3:
		var f: Array = fruits[(k + seed) % fruits.size()]
		var cx := -0.62 + k * 0.62
		for n in 46:
			var a := r.next() * TAU; var rr := sqrt(r.next()) * 0.26
			var h := 0.84 + (0.26 - rr) * 0.9 + r.next() * 0.03
			mb.ball(Vector3(cx + cos(a) * rr, h, sin(a) * rr * 1.6), f[1], (f[0] as Color) * r.range_f(0.85, 1.1), g(GM.PAINT, 0.45), 5, 3)
	# hanging banana bunches on a cross bar
	mb.tube(Vector3(-0.9, 1.75, 0), Vector3(0.9, 1.75, 0), 0.02, 4, wood, g(GM.WOOD, 0.8))
	for x in [-0.9, 0.9]: mb.tube(Vector3(x, 0.86, 0), Vector3(x, 1.8, 0), 0.025, 4, wood, g(GM.WOOD, 0.8))
	for b in 4:
		var bx := -0.6 + b * 0.4
		for k in 10:
			var a := k * 0.63
			var c := Vector3(bx + cos(a) * 0.07, 1.6 - k * 0.022, sin(a) * 0.07)
			mb.tube(c, c + Vector3(cos(a) * 0.06, -0.14, sin(a) * 0.06), 0.017, 4, Rng.hex_lin("#e8c21a") * r.range_f(0.85, 1.05), g(GM.PAINT, 0.5))
	return mb.to_mesh(Mats.generic())

## flower seller's spread: mat, baskets of jasmine strings and marigold, a few rose heaps
static func _flower_mat(seed: int) -> ArrayMesh:
	var r := Rng.new(seed)
	var mb := MB.new(false)
	mb.box(Vector3(0, 0.01, 0), Vector3(0.8, 0.01, 0.55), 0.0, Rng.hex_lin("#b89a5a"), g(GM.CLOTH, 0.9))   # palm-leaf mat
	var heaps := [[Rng.hex_lin("#f4f2ea"), 0.016], [Rng.hex_lin("#f39a0e"), 0.022], [Rng.hex_lin("#f4f2ea"), 0.016], [Rng.hex_lin("#c0142a"), 0.02], [Rng.hex_lin("#ffd21a"), 0.022]]
	for k in 5:
		var c := Vector3(-0.55 + (k % 3) * 0.55, 0.0, -0.22 + (k / 3) * 0.44)
		mb.cylinder(c.x, 0.02, c.z, 0.2, 0.09, 10, Rng.hex_lin("#8a6a3a"), g(GM.WOOD, 0.9), Vector4.ZERO, true, 0.23)   # basket
		var h: Array = heaps[k]
		for n in 40:
			var a := r.next() * TAU; var rr := sqrt(r.next()) * 0.19
			mb.ball(c + Vector3(cos(a) * rr, 0.11 + (0.19 - rr) * 0.5, sin(a) * rr), h[1], (h[0] as Color) * r.range_f(0.9, 1.05), g(GM.CLOTH, 0.7), 4, 2)
	# jasmine strings coiled into balls (madurai malli) and a hanging string from a stick
	mb.tube(Vector3(0.8, 0.0, 0.5), Vector3(0.8, 1.3, 0.5), 0.015, 4, Rng.hex_lin("#5a4a3a"), g(GM.WOOD, 0.9))
	for k in 8:
		mb.ball(Vector3(0.8, 1.25 - k * 0.07, 0.53), 0.03, Rng.hex_lin("#f6f4ec"), g(GM.CLOTH, 0.6), 5, 3)
	return mb.to_mesh(Mats.generic())

## tender-coconut seller's heap (green coconuts, a few husked white ones) and the chopping block
static func _coconuts(seed: int) -> ArrayMesh:
	var r := Rng.new(seed)
	var mb := MB.new(false)
	for n in 34:
		var a := r.next() * TAU; var rr := sqrt(r.next()) * 0.55
		var col := Rng.hex_lin("#5e8a22") if r.next() < 0.85 else Rng.hex_lin("#d9c79a")
		mb.ball(Vector3(cos(a) * rr, 0.1 + (0.55 - rr) * 0.45, sin(a) * rr), r.range_f(0.09, 0.11), col * r.range_f(0.8, 1.1), g(GM.PAINT, 0.6), 6, 4, 1.15)
	mb.cylinder(0.8, 0.0, 0.0, 0.18, 0.45, 8, Rng.hex_lin("#6a4a2a"), g(GM.WOOD, 0.9))
	mb.box(Vector3(0.8, 0.5, 0.0), Vector3(0.18, 0.01, 0.025), 0.3, Rng.hex_lin("#9a9a9a"), g(GM.METAL, 0.3))   # aruval
	return mb.to_mesh(Mats.generic())

## flex hoarding frame: two steel posts and a timber/steel backing; the print is a poster quad
static func _hoarding() -> ArrayMesh:
	var mb := MB.new(false)
	var steel := Rng.hex_lin("#4a4a48")
	for x in [-1.6, 1.6]:
		mb.tube(Vector3(x, 0, -0.05), Vector3(x, 6.6, -0.05), 0.05, 6, steel, g(GM.RUST, 0.7))
		mb.tube(Vector3(x, 0, -0.05), Vector3(x * 0.8, 3.0, -0.9), 0.035, 5, steel, g(GM.RUST, 0.7))   # strut
	for y in [2.4, 4.4, 6.4]:
		mb.beam(Vector3(-1.75, y, -0.08), Vector3(1.75, y, -0.08), 0.06, 0.06, steel, g(GM.RUST, 0.7))
	mb.box(Vector3(0, 4.4, -0.1), Vector3(1.6, 2.1, 0.01), 0.0, Rng.hex_lin("#3a3a38"), g(GM.TARP, 0.9))
	return mb.to_mesh(Mats.generic())
