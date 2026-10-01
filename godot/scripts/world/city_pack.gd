class_name CityPack
extends RefCounted
## A city data pack (pack.json, style.json, names.json and its regions). The engine never
## hard-codes a city: everything here comes from `res://packs/<city>/`.

var id: String
var root: String
var pack: Dictionary
var style: Dictionary
var names: Dictionary
var region: Dictionary          # meta.json of the active region
var region_dir: String
var road_names: PackedStringArray
var chunk_size := 200.0
var bounds := Rect2()           # x0, z0 → size in metres
var _coast := PackedVector2Array()
var _seg_grid := {}             # spatial hash of road segments
const SH := 30.0

static func load_json(path: String):
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("missing " + path)
		return null
	return JSON.parse_string(f.get_as_text())

func _init(city: String) -> void:
	id = city
	root = "res://packs/%s/" % city
	pack = load_json(root + "pack.json")
	style = load_json(root + "style.json")
	names = load_json(root + "names.json")
	load_region(pack.spawn.region)

func load_region(rid: String) -> void:
	region_dir = root + "regions/%s/" % rid
	region = load_json(region_dir + "meta.json")
	chunk_size = float(region.chunkSize)
	var b: Array = region.bounds
	bounds = Rect2(b[0], b[1], b[2] - b[0], b[3] - b[1])
	road_names = PackedStringArray()
	for r in region.roads: road_names.append(r.name)
	_coast.clear()
	var c: Array = region.coast
	for i in range(0, c.size() - 1, 2): _coast.append(Vector2(c[i], c[i + 1]))
	_index_roads()

func load_chunk(key: String) -> Array:
	var d = load_json(region_dir + "chunks/%s.json" % key)
	return d.b if d else []

func has_coast() -> bool:
	return _coast.size() >= 2

## x of the shoreline (surf line) at a given z; the sea lies at larger x
func coast_x(z: float) -> float:
	if _coast.size() < 2: return INF
	if z <= _coast[0].y: return _coast[0].x
	for i in _coast.size() - 1:
		if z <= _coast[i + 1].y:
			var t := (z - _coast[i].y) / maxf(_coast[i + 1].y - _coast[i].y, 0.001)
			return lerpf(_coast[i].x, _coast[i + 1].x, t)
	return _coast[_coast.size() - 1].x

func chunk_center(key: String) -> Vector2:
	var p := key.split("_")
	return Vector2(bounds.position.x + (int(p[0]) + 0.5) * chunk_size, bounds.position.y + (int(p[1]) + 0.5) * chunk_size)

static func pts2(arr: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(0, arr.size() - 1, 2): out.append(Vector2(arr[i], arr[i + 1]))
	if out.size() > 2 and out[0].distance_to(out[out.size() - 1]) < 0.01: out.remove_at(out.size() - 1)
	return out

# ------------------------------------------------------------------------------------ road queries
func _index_roads() -> void:
	_seg_grid.clear()
	var roads: Array = region.roads
	for ri in roads.size():
		var P: Array = roads[ri].pts
		for i in range(0, P.size() / 2 - 1):
			var ax: float = P[i * 2]; var az: float = P[i * 2 + 1]; var bx: float = P[i * 2 + 2]; var bz: float = P[i * 2 + 3]
			for gx in range(floori(minf(ax, bx) / SH), floori(maxf(ax, bx) / SH) + 1):
				for gz in range(floori(minf(az, bz) / SH), floori(maxf(az, bz) / SH) + 1):
					var k := Vector2i(gx, gz)
					if not _seg_grid.has(k): _seg_grid[k] = PackedInt32Array()
					_seg_grid[k].append(ri); _seg_grid[k].append(i)

## nearest point on a road of rank >= min_rank within max_d metres, or {} if none
func nearest_road(x: float, z: float, max_d := 40.0, min_rank := 1) -> Dictionary:
	var best := {}
	var bd := max_d
	var seen := {}
	var roads: Array = region.roads
	for gx in range(floori((x - max_d) / SH), floori((x + max_d) / SH) + 1):
		for gz in range(floori((z - max_d) / SH), floori((z + max_d) / SH) + 1):
			var c = _seg_grid.get(Vector2i(gx, gz))
			if c == null: continue
			for k in range(0, c.size(), 2):
				var ri: int = c[k]; var i: int = c[k + 1]
				var key := ri * 4096 + i
				if seen.has(key): continue
				seen[key] = true
				var r: Dictionary = roads[ri]
				if int(r.rank) < min_rank: continue
				var P: Array = r.pts
				var a := Vector2(P[i * 2], P[i * 2 + 1]); var b := Vector2(P[i * 2 + 2], P[i * 2 + 3])
				var ab := b - a
				var t := clampf((Vector2(x, z) - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
				var p := a + ab * t
				var d := p.distance_to(Vector2(x, z))
				if d < bd:
					bd = d
					best = {"ri": ri, "seg": i, "p": p, "d": d, "t": t, "dir": ab.normalized(), "w": float(r.w)}
	return best
