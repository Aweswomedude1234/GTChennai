class_name Mats
extends RefCounted
## Shared materials (one instance each, so thousands of buildings share a handful of draw states).

static var _cache := {}

static func tex(name: String) -> Texture2D:
	var k := "t:" + name
	if not _cache.has(k): _cache[k] = load("res://textures/%s.png" % name)
	return _cache[k]

static func _shader(name: String, params: Array) -> ShaderMaterial:
	if _cache.has(name): return _cache[name]
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/%s.gdshader" % name)
	for p in params: m.set_shader_parameter(p, tex(p))
	_cache[name] = m
	return m

static func road() -> ShaderMaterial: return _shader("road", ["asphalt_c", "asphalt_n", "earth_c", "noise"])
static func ground() -> ShaderMaterial: return _shader("ground", ["earth_c", "earth_n", "grass_c", "grass_n", "sand_c", "sand_n", "granite_c", "granite_n", "concrete_c", "concrete_n", "noise"])
static func generic() -> ShaderMaterial: return _shader("generic", ["plaster_n", "concrete_c", "concrete_n", "granite_c", "granite_n", "pavers_c", "pavers_n", "brick_c", "brick_n", "rooftile_c", "rooftile_n", "sand_c", "cloth_n", "noise"])
static func facade() -> ShaderMaterial: return _shader("facade", ["plaster_n", "brick_c", "noise"])
static func sea() -> ShaderMaterial: return _shader("sea", ["noise"])
static func water() -> ShaderMaterial: return _shader("water", ["noise"])

static func sign(atlas: Texture2D, rows: int) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/sign.gdshader")
	m.set_shader_parameter("atlas", atlas)
	m.set_shader_parameter("rows", float(rows))
	m.set_shader_parameter("cols", float(BuildingGen.SIGN_COLS))
	return m
