class_name MB
extends RefCounted
## Mesh builder for procedural geometry. Thread-safe (plain packed arrays); call `arrays()` in a
## worker and `to_mesh()` / `ArrayMesh.add_surface_from_arrays` on any thread.
## Godot's front faces are clockwise, so quads take the intended outward normal and fix winding.
## Vertex layout: VERTEX, NORMAL, COLOR (linear albedo), UV, CUSTOM0 (vec4), CUSTOM1 (vec4).

var v := PackedVector3Array()
var n := PackedVector3Array()
var col := PackedColorArray()
var uv := PackedVector2Array()
var c0 := PackedFloat32Array()
var c1 := PackedFloat32Array()
var idx := PackedInt32Array()
var use_c1 := true

func _init(with_c1 := true) -> void:
	use_c1 = with_c1

func count() -> int:
	return v.size()

func vert(p: Vector3, nrm: Vector3, color: Color, t: Vector2, a: Vector4, b := Vector4.ZERO) -> int:
	v.append(p); n.append(nrm); col.append(color); uv.append(t)
	c0.append(a.x); c0.append(a.y); c0.append(a.z); c0.append(a.w)
	if use_c1:
		c1.append(b.x); c1.append(b.y); c1.append(b.z); c1.append(b.w)
	return v.size() - 1

## quad a-b-c-d in order around its edge; `nrm` is the intended facing direction
func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, nrm: Vector3, color: Color, p0: Vector4, p1 := Vector4.ZERO,
		t0 := Vector2(0, 0), t1 := Vector2(1, 0), t2 := Vector2(1, 1), t3 := Vector2(0, 1)) -> void:
	var base := v.size()
	vert(a, nrm, color, t0, p0, p1); vert(b, nrm, color, t1, p0, p1)
	vert(c, nrm, color, t2, p0, p1); vert(d, nrm, color, t3, p0, p1)
	var ccw := (b - a).cross(c - a).dot(nrm) > 0.0
	if ccw:
		idx.append_array([base, base + 2, base + 1, base, base + 3, base + 2])
	else:
		idx.append_array([base, base + 1, base + 2, base, base + 2, base + 3])

func tri(a: Vector3, b: Vector3, c: Vector3, nrm: Vector3, color: Color, p0: Vector4, p1 := Vector4.ZERO,
		t0 := Vector2.ZERO, t1 := Vector2(1, 0), t2 := Vector2(0, 1)) -> void:
	var base := v.size()
	vert(a, nrm, color, t0, p0, p1); vert(b, nrm, color, t1, p0, p1); vert(c, nrm, color, t2, p0, p1)
	if (b - a).cross(c - a).dot(nrm) > 0.0: idx.append_array([base, base + 2, base + 1])
	else: idx.append_array([base, base + 1, base + 2])

## box centred at c with half extents h, rotated by `rot` about Y (local +z is the facing side).
## UVs are in metres so materials can tile.
func box(c: Vector3, h: Vector3, rot: float, color: Color, p0: Vector4, p1 := Vector4.ZERO, skip_bottom := true) -> void:
	var cs := cos(rot); var sn := sin(rot)
	var T := func(x: float, y: float, z: float) -> Vector3: return Vector3(c.x + x * cs + z * sn, c.y + y, c.z - x * sn + z * cs)
	var N := func(x: float, y: float, z: float) -> Vector3: return Vector3(x * cs + z * sn, y, -x * sn + z * cs)
	var p := [T.call(-h.x, -h.y, -h.z), T.call(h.x, -h.y, -h.z), T.call(h.x, h.y, -h.z), T.call(-h.x, h.y, -h.z),
		T.call(-h.x, -h.y, h.z), T.call(h.x, -h.y, h.z), T.call(h.x, h.y, h.z), T.call(-h.x, h.y, h.z)]
	var ux := Vector2(h.x * 2, 0); var uy := Vector2(0, h.y * 2); var uz := Vector2(h.z * 2, 0)
	quad(p[4], p[5], p[6], p[7], N.call(0, 0, 1), color, p0, p1, Vector2.ZERO, ux, ux + uy, uy)
	quad(p[1], p[0], p[3], p[2], N.call(0, 0, -1), color, p0, p1, Vector2.ZERO, ux, ux + uy, uy)
	quad(p[5], p[1], p[2], p[6], N.call(1, 0, 0), color, p0, p1, Vector2.ZERO, uz, uz + uy, uy)
	quad(p[0], p[4], p[7], p[3], N.call(-1, 0, 0), color, p0, p1, Vector2.ZERO, uz, uz + uy, uy)
	quad(p[3], p[7], p[6], p[2], N.call(0, 1, 0), color, p0, p1, Vector2.ZERO, ux, ux + Vector2(0, h.z * 2), Vector2(0, h.z * 2))
	if not skip_bottom:
		quad(p[0], p[1], p[5], p[4], N.call(0, -1, 0), color, p0, p1)

## box spanning two points (a beam / pole / rail) with square section `w`×`hgt`
func beam(a: Vector3, b: Vector3, w: float, hgt: float, color: Color, p0: Vector4, p1 := Vector4.ZERO) -> void:
	var d := b - a
	var L := d.length()
	if L < 0.001: return
	var f := d / L
	var up := Vector3.UP if absf(f.y) < 0.95 else Vector3.RIGHT
	var s := f.cross(up).normalized() * (w * 0.5)
	var u := s.cross(f).normalized() * (hgt * 0.5)
	var corners := [a - s - u, a + s - u, a + s + u, a - s + u]
	for i in 4:
		var c0v: Vector3 = corners[i]; var c1v: Vector3 = corners[(i + 1) % 4]
		var mid := (c0v + c1v) * 0.5 - a
		var nrm := (mid - f * mid.dot(f)).normalized()
		quad(c0v, c1v, c1v + d, c0v + d, nrm, color, p0, p1, Vector2.ZERO, Vector2(w, 0), Vector2(w, L), Vector2(0, L))

## vertical cylinder from y0 up by h, optional domed cap
func cylinder(cx: float, y0: float, cz: float, r: float, h: float, seg: int, color: Color, p0: Vector4, p1 := Vector4.ZERO, cap := true, r_top := -1.0) -> void:
	if r_top < 0: r_top = r
	var base := v.size()
	for i in seg + 1:
		var ang := float(i) / seg * TAU
		var x := cos(ang); var z := sin(ang)
		var nrm := Vector3(x, (r - r_top) / maxf(h, 0.01), z).normalized()
		vert(Vector3(cx + x * r, y0, cz + z * r), nrm, color, Vector2(float(i) / seg * TAU * r, 0), p0, p1)
		vert(Vector3(cx + x * r_top, y0 + h, cz + z * r_top), nrm, color, Vector2(float(i) / seg * TAU * r, h), p0, p1)
	for i in seg:
		var k := base + i * 2
		idx.append_array([k, k + 3, k + 1, k, k + 2, k + 3])
	_fix_last_tris(base, seg * 6)
	if cap:
		var top := vert(Vector3(cx, y0 + h + r_top * 0.12, cz), Vector3.UP, color, Vector2.ZERO, p0, p1)
		var first := v.size()
		for i in seg + 1:
			var ang := float(i) / seg * TAU
			vert(Vector3(cx + cos(ang) * r_top, y0 + h, cz + sin(ang) * r_top), Vector3(cos(ang) * 0.3, 0.95, sin(ang) * 0.3).normalized(), color, Vector2(cos(ang), sin(ang)), p0, p1)
		for i in seg:
			idx.append_array([top, first + i + 1, first + i])
		_fix_last_tris(top, seg * 3)

## cylinder between two arbitrary points (pipes, poles, cables)
func tube(a: Vector3, b: Vector3, r: float, seg: int, color: Color, p0: Vector4, p1 := Vector4.ZERO, r_b := -1.0) -> void:
	if r_b < 0: r_b = r
	var d := b - a
	var L := d.length()
	if L < 0.001: return
	var f := d / L
	var up := Vector3.UP if absf(f.y) < 0.95 else Vector3.RIGHT
	var s := f.cross(up).normalized()
	var u := s.cross(f).normalized()
	var base := v.size()
	for i in seg + 1:
		var ang := float(i) / seg * TAU
		var dir := s * cos(ang) + u * sin(ang)
		vert(a + dir * r, dir, color, Vector2(float(i) / seg, 0), p0, p1)
		vert(b + dir * r_b, dir, color, Vector2(float(i) / seg, L), p0, p1)
	for i in seg:
		var k := base + i * 2
		idx.append_array([k, k + 1, k + 3, k, k + 3, k + 2])
	_fix_last_tris(base, seg * 6)

## a sagging cable (catenary approximation) as a thin tube polyline
## low-poly UV sphere (fruit, coconuts, heaps); `squash` scales y
func ball(c: Vector3, r: float, color: Color, p0: Vector4, seg := 6, rings := 4, squash := 1.0) -> void:
	var base := v.size()
	for j in rings + 1:
		var th := PI * float(j) / rings
		for i in seg + 1:
			var ph := TAU * float(i) / seg
			var d := Vector3(sin(th) * cos(ph), cos(th), sin(th) * sin(ph))
			vert(c + Vector3(d.x * r, d.y * r * squash, d.z * r), d, color, Vector2(float(i) / seg, float(j) / rings), p0)
	for j in rings:
		for i in seg:
			var a := base + j * (seg + 1) + i
			var b := a + seg + 1
			idx.append_array([a, a + 1, b, a + 1, b + 1, b])
	_fix_last_tris(base, rings * seg * 6)

func cable(a: Vector3, b: Vector3, sag: float, r: float, color: Color, p0: Vector4, segs := 8) -> void:
	var prev := a
	for i in range(1, segs + 1):
		var t := float(i) / segs
		var p := a.lerp(b, t)
		p.y -= sag * 4.0 * t * (1.0 - t)
		tube(prev, p, r, 3, color, p0)
		prev = p

## flat polygon (pts in xz) triangulated by the caller (`tris` index triples into pts) at height y
func polygon(pts: PackedVector2Array, tris: PackedInt32Array, y: float, up: bool, color: Color, p0: Vector4, p1 := Vector4.ZERO) -> void:
	var base := v.size()
	var nrm := Vector3.UP if up else Vector3.DOWN
	for p in pts: vert(Vector3(p.x, y, p.y), nrm, color, p, p0, p1)
	for i in range(0, tris.size(), 3):
		var a := pts[tris[i]]; var b := pts[tris[i + 1]]; var c := pts[tris[i + 2]]
		# winding in xz: cross.y of (b-a)x(c-a) with y-up; choose order facing nrm
		var cy := (c.x - a.x) * (b.y - a.y) - (b.x - a.x) * (c.y - a.y)
		var facing_up := cy > 0.0
		if facing_up == up: idx.append_array([base + tris[i], base + tris[i + 2], base + tris[i + 1]])
		else: idx.append_array([base + tris[i], base + tris[i + 1], base + tris[i + 2]])

## ensure the last `n_idx` indices (triangles) face along their vertex normals
func _fix_last_tris(base_v: int, n_idx: int) -> void:
	var s := idx.size() - n_idx
	for i in range(s, idx.size(), 3):
		var a := v[idx[i]]; var b := v[idx[i + 1]]; var c := v[idx[i + 2]]
		var nn := n[idx[i]] + n[idx[i + 1]] + n[idx[i + 2]]
		if (b - a).cross(c - a).dot(nn) > 0.0:
			var t := idx[i + 1]; idx[i + 1] = idx[i + 2]; idx[i + 2] = t

func append(o: MB) -> void:
	var off := v.size()
	v.append_array(o.v); n.append_array(o.n); col.append_array(o.col); uv.append_array(o.uv)
	c0.append_array(o.c0)
	if use_c1 and o.use_c1: c1.append_array(o.c1)
	for i in o.idx: idx.append(i + off)

func arrays() -> Array:
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = n
	arr[Mesh.ARRAY_COLOR] = col
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_CUSTOM0] = c0
	if use_c1: arr[Mesh.ARRAY_CUSTOM1] = c1
	arr[Mesh.ARRAY_INDEX] = idx
	return arr

func format_flags() -> int:
	var f := Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
	if use_c1: f |= Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT
	return f

func add_to(mesh: ArrayMesh, mat: Material = null) -> int:
	if v.is_empty(): return -1
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays(), [], {}, format_flags())
	var s := mesh.get_surface_count() - 1
	if mat: mesh.surface_set_material(s, mat)
	return s

func to_mesh(mat: Material = null) -> ArrayMesh:
	var m := ArrayMesh.new()
	add_to(m, mat)
	return m
