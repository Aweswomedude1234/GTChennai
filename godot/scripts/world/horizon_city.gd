class_name HorizonCity
extends RefCounted
## The cheapest LOD: every building in the region as a simple box (walls carry the façade shader's
## far mode through cell kind 1 with large cells), one mesh per chunk shown only when that chunk is
## not streamed, plus a synthetic ring of city blocks beyond the region so Chennai continues to the
## horizon instead of ending in an empty plain.

var pack: CityPack
var chunk_meshes := {}     # key → ArrayMesh
var ring_mesh: ArrayMesh

func _init(p: CityPack) -> void:
	pack = p

## run on a worker thread
func build() -> void:
	var style: Dictionary = pack.style
	for key in pack.region.chunks:
		var mb := MB.new(true)
		for b in pack.load_chunk(key): _box_building(mb, b, style)
		if mb.count() > 0: chunk_meshes[key] = mb.to_mesh(Mats.facade())
	ring_mesh = _ring(style)

func _box_building(mb: MB, b: Dictionary, style: Dictionary) -> void:
	var P := CityPack.pts2(b.f)
	if P.size() < 3: return
	var r := Rng.new(int(b.s))
	var levels := maxi(1, int(b.l))
	var H: float = float(b.h) if b.has("h") and float(b.h) > 0 else 3.3 + (levels - 1) * 3.1
	if b.k == "mandapam": H = 5.0
	if b.k == "lighthouse": return
	var pal: Array = style.paint.get(b.k, style.paint.residential)
	var paint := Rng.hex_lin(r.pick(pal))
	for i in P.size():
		var a := P[i]; var c := P[(i + 1) % P.size()]
		var L := a.distance_to(c)
		if L < 0.5: continue
		var t := (c - a) / L
		var nrm := Vector3(t.y, 0, -t.x)
		var nb := maxi(1, roundi(L / 3.4))
		for j in nb:
			var p0 := a + t * (L * j / nb); var p1 := a + t * (L * (j + 1) / nb)
			for f in levels:
				var y0 := 0.0 if f == 0 else 3.3 + (f - 1) * 3.1
				var y1 := 3.3 + f * 3.1 if f < levels - 1 else H
				var kind := 3 if (f == 0 and b.k == "commercial" and int(b.e[i] if i < b.e.size() else 0) > 0) else 1
				mb.quad(Vector3(p0.x, y0, p0.y), Vector3(p1.x, y0, p1.y), Vector3(p1.x, y1, p1.y), Vector3(p0.x, y1, p0.y), nrm, paint,
					Vector4(r.next(), 1, kind, 0.5), Vector4(L / nb, y1 - y0, f, 0.5))
	var tris := Geometry2D.triangulate_polygon(P)
	if not tris.is_empty():
		mb.polygon(P, tris, H, true, paint.lerp(Rng.hex_lin("#8a8478"), 0.6), Vector4(0, 0, 8, 0.5), Vector4(4, 4, 0, 0.5))

## synthetic blocks in a 2.6 km ring around the region (west, north, south; the east is the sea)
func _ring(style: Dictionary) -> ArrayMesh:
	var mb := MB.new(true)
	var b := pack.bounds
	var r := Rng.new(77)
	var step := 30.0
	var x := b.position.x - 2600.0
	while x < b.end.x + 2600.0:
		var z := b.position.y - 2600.0
		while z < b.end.y + 2600.0:
			var inside := b.grow(-10.0).has_point(Vector2(x, z))
			var sea := pack.has_coast() and x > pack.coast_x(z) - 90.0
			var far := not b.grow(1100.0).has_point(Vector2(x, z))
			if far and (int(x / step) + int(z / step)) % 2 != 0: inside = true  # half density far out: merged blocks
			if not inside and not sea and r.next() < 0.82:
				# a block of 2–4 plot buildings along a street (one merged block when far)
				var n := 1 if far else 2 + int(r.next() * 3.0)
				for k in n:
					var w := r.range_f(5.0, 10.0) * (3.0 if far else 1.0); var d := r.range_f(8.0, 15.0) * (1.8 if far else 1.0)
					var cx := x + r.range_f(-8.0, 8.0); var cz := z + r.range_f(-8.0, 8.0)
					var lv := 1 + r.pick_w([10, 30, 30, 18, 8, 4])
					if r.next() < 0.04: lv = 6 + int(r.next() * 8.0)
					var H := 3.3 + (lv - 1) * 3.1
					var paint := Rng.hex_lin(r.pick(style.paint.residential if r.next() < 0.7 else style.paint.commercial))
					var P := PackedVector2Array([Vector2(cx - w * 0.5, cz - d * 0.5), Vector2(cx + w * 0.5, cz - d * 0.5), Vector2(cx + w * 0.5, cz + d * 0.5), Vector2(cx - w * 0.5, cz + d * 0.5)])
					for i in 4:
						var a := P[i]; var c := P[(i + 1) % 4]
						var t := (c - a).normalized()
						mb.quad(Vector3(a.x, 0, a.y), Vector3(c.x, 0, c.y), Vector3(c.x, H, c.y), Vector3(a.x, H, a.y), Vector3(t.y, 0, -t.x), paint,
							Vector4(r.next(), 1, 1, 0.5), Vector4(a.distance_to(c), H, 0, 0.5))
					mb.quad(Vector3(P[0].x, H, P[0].y), Vector3(P[1].x, H, P[1].y), Vector3(P[2].x, H, P[2].y), Vector3(P[3].x, H, P[3].y), Vector3.UP, paint.lerp(Rng.hex_lin("#8a8478"), 0.6), Vector4(0, 0, 8, 0.5), Vector4(4, 4, 0, 0.5))
			z += step
		x += step
	return mb.to_mesh(Mats.facade())
