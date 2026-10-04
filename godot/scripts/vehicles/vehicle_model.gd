class_name VehicleModel
extends Node3D
## A vehicle body from godot/assets/vehicles/<kind>_<variant>.glb (tools/vehicles/build_vehicles.py).
## Blender material names map to the vehicle shaders: "paint"/"paint2" → vehicle.gdshader with
## per-instance colours (so one mesh gives every colour on the road), "glass" → vehicle_glass,
## lamp_* → lenses that light at night / when braking / blinking. Other materials (chrome, trim,
## rubber, seat …) keep their imported PBR values. Wheels are the `wheel_<i>` child nodes.

const VARIANTS := {"auto": 3, "hatch": 4, "bike": 3, "scooter": 3, "bus": 2, "lorry": 2, "minitruck": 2, "cycle": 1}
## paint palettes (sRGB hex), weighted by repetition: what you actually see on Chennai roads
const PALETTE := {
	"auto": [["#f2b705", "#1f5e2e"], ["#f4c20d", "#1f5e2e"], ["#f0b400", "#173d24"], ["#efb50a", "#111111"], ["#f2b705", "#1f5e2e"], ["#e8b10a", "#1b4f8a"]],
	"hatch": ["#f2f2f0", "#f2f2f0", "#f4f4f2", "#c8c8c8", "#b8b8ba", "#8a8a8a", "#7a1414", "#1c3a6a", "#2a2a2a", "#d8d0b8", "#3c5a3a", "#5e2a6e", "#9a2a1a", "#e8e4dc"],
	"bike": ["#151515", "#151515", "#0d0d0d", "#8a1010", "#1a3a8a", "#5a5a5a", "#3a0a0a", "#c7c7c7", "#1d4a2a"],
	"scooter": ["#f5f5f5", "#151515", "#8a1010", "#1a3a8a", "#7f8c8d", "#2e7d32", "#5e2a6e", "#c8a46a", "#d0d0d0"],
	"lorry": [["#e8731a", "#1f5ea8"], ["#d9a21a", "#b02a1a"], ["#2a7a3a", "#e8c21a"], ["#1f5ea8", "#e8731a"], ["#b02a1a", "#e8c21a"]],
	"minitruck": ["#f2f2f0", "#f2f2f0", "#e8e4d8", "#3a6aa8", "#c8c8c8"],
	"cycle": ["#141414", "#141414", "#1a2a5a", "#5a1a1a", "#2a4a2a"],
	"bus": [["#2a5db0", "#f2f0ea"], ["#2a5db0", "#f2f0ea"], ["#2f8a4a", "#f2f0ea"], ["#a52a2a", "#f2c811"], ["#1f3f8a", "#e8e4d8"]],
}
## object-space height band painted with the second colour (auto-rickshaw green skirt)
const BAND := {"auto": Vector4(-1.0, 0.52, -10.0, -10.0)}

static var _scenes := {}
static var _mats := {}

var kind := ""
var wheels: Array[Node3D] = []
var meshes: Array[MeshInstance3D] = []

static func scene(kind_: String, variant: int) -> PackedScene:
	var path := "res://assets/vehicles/%s_%d.glb" % [kind_, variant % VARIANTS.get(kind_, 1)]
	if not _scenes.has(path): _scenes[path] = load(path)
	return _scenes[path]

static func _material(role: String) -> Material:
	if _mats.has(role): return _mats[role]
	var m := ShaderMaterial.new()
	match role:
		"glass": m.shader = load("res://shaders/vehicle_glass.gdshader")
		_:
			m.shader = load("res://shaders/vehicle.gdshader")
			m.set_shader_parameter("part", {"paint": 0, "paint2": 0, "lamp_head": 2, "lamp_tail": 3, "lamp_ind": 4}[role])
			m.set_shader_parameter("second", role == "paint2")
	_mats[role] = m
	return m

static func make(kind_: String, seed: int) -> VehicleModel:
	var r := Rng.new(seed)
	var vm := VehicleModel.new()
	vm.kind = kind_
	vm.name = "model"
	var inst: Node3D = scene(kind_, int(r.next() * 97.0)).instantiate()
	vm.add_child(inst)
	vm._collect(inst)
	vm.recolour(seed)
	return vm

## the paint colours a given seed gets (same for the full body and the far MultiMesh tier)
static func paint_for(kind_: String, seed: int) -> Array:
	var r := Rng.new(seed * 7 + 3)
	var pal = r.pick(PALETTE.get(kind_, ["#888888"]))
	if pal is Array: return [Color(pal[0]), Color(pal[1])]
	return [Color(pal), Color("#1a1a1a")]

## new random paint / dirt / age for this body (pooled traffic reuses bodies)
func recolour(seed: int) -> void:
	var cs := paint_for(kind, seed)
	set_paint(cs[0], cs[1])
	var r := Rng.new(seed * 7 + 3)
	r.next()
	set_param("dirt", r.range_f(0.15, 0.8))
	set_param("age", r.range_f(0.05, 0.7) if kind != "bus" else r.range_f(0.3, 0.9))
	set_param("band", BAND.get(kind, Vector4(-10, -10, -10, -10)))
	set_param("brake", 0.0)
	set_param("blink", 0.0)

func _collect(n: Node) -> void:
	for c in n.get_children():
		if c.name.begins_with("wheel_"):
			wheels.append(c)
		if c is MeshInstance3D:
			var mi: MeshInstance3D = c
			meshes.append(mi)
			for s in mi.mesh.get_surface_count():
				var m := mi.mesh.surface_get_material(s)
				if m == null: continue
				var role := m.resource_name
				if role in ["paint", "paint2", "glass", "lamp_head", "lamp_tail", "lamp_ind"]:
					mi.set_surface_override_material(s, _material(role))
		_collect(c)
	wheels.sort_custom(func(a, b): return String(a.name) < String(b.name))

func set_paint(c1: Color, c2: Color) -> void:
	set_param("paint", c1)
	set_param("paint2", c2)

func set_param(p: String, v: Variant) -> void:
	for mi in meshes: mi.set_instance_shader_parameter(p, v)

## hub positions in the vehicle's local frame (for physics mounts) and wheel radii
func wheel_info() -> Array:
	var out := []
	for w in wheels:
		var aabb := (w as MeshInstance3D).get_aabb() if w is MeshInstance3D else AABB(Vector3.ZERO, Vector3.ONE * 0.6)
		var t := w.transform
		var par := w.get_parent()
		while par != null and par != self:
			t = (par as Node3D).transform * t
			par = par.get_parent()
		var p := t.origin
		out.append({"p": p, "r": aabb.size.y * 0.5, "node": w})
	return out

## The whole model (body + wheels at rest) merged into one mesh in the generic prop vertex format
## (COLOR = linear albedo, CUSTOM0 = type/roughness) for MultiMesh rows of parked two-wheelers and
## distant traffic. Painted panels are white so the per-instance colour tints them.
static func baked(kind_: String, variant: int, lo := false) -> ArrayMesh:
	var GM := BuildingGen.GM
	var path := "res://assets/vehicles/%s_%d%s.glb" % [kind_, variant % VARIANTS.get(kind_, 1), "_lo" if lo else ""]
	if lo and not ResourceLoader.exists(path): path = path.replace("_lo", "")
	var root: Node3D = (load(path) as PackedScene).instantiate()
	var mb := MB.new(false)
	var stack: Array = [[root, Transform3D.IDENTITY]]
	while not stack.is_empty():
		var it: Array = stack.pop_back()
		var node: Node = it[0]
		var xf: Transform3D = it[1]
		for c in node.get_children():
			if c is Node3D: stack.append([c, xf * (c as Node3D).transform])
		if not (node is MeshInstance3D): continue
		var mesh: Mesh = (node as MeshInstance3D).mesh
		var nb := xf.basis.inverse().transposed()
		for s in mesh.get_surface_count():
			var m := mesh.surface_get_material(s)
			var role := m.resource_name if m else ""
			var col := Color(0.5, 0.5, 0.5)
			var rough := 0.5
			if m is BaseMaterial3D:
				col = (m as BaseMaterial3D).albedo_color.srgb_to_linear()
				rough = (m as BaseMaterial3D).roughness
			var g := Vector4(GM.PAINT, rough, 0, 0)
			match role:
				"paint": col = Color(0.85, 0.85, 0.85); g = Vector4(GM.PAINT, 0.3, 0, 0)
				"glass": g = Vector4(GM.GLASS, 0.05, 0, 0)
				"chrome", "rim", "metal", "engine": g = Vector4(GM.METAL, rough, 0, 0)
				"rubber": g = Vector4(GM.RUBBER, 0.85, 0, 0)
				"seat", "canvas", "interior": g = Vector4(GM.CLOTH, 0.7, 0, 0)
			var arr := mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var nrms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			var base := mb.count()
			for i in verts.size():
				mb.vert(xf * verts[i], (nb * nrms[i]).normalized(), col, Vector2(verts[i].x + verts[i].y, verts[i].z), g)
			var ind: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			if ind.is_empty():
				for i in verts.size(): mb.idx.append(base + i)
			else:
				for i in ind: mb.idx.append(base + i)
	root.free()
	return mb.to_mesh(Mats.generic())
