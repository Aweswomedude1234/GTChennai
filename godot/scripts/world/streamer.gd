class_name Streamer
extends Node3D
## Chunk streaming with two LOD rings. Near chunks get full detail (signs, chajjas, roof clutter,
## street furniture), shadows and colliders; far chunks get the simplified shell. Meshes are
## generated on WorkerThreadPool threads; the main thread only uploads (budgeted per frame).

signal chunk_near(key: String, rec: Dictionary)
signal chunk_unloaded(key: String, rec: Dictionary)

var pack: CityPack
var painter: SignPainter
var near_r := 340.0
var far_r := 1400.0
var chunks := {}     # key → {cx, cz, center, state, pending, node, shops, lights, ...}
var _mutex := Mutex.new()
var _done: Array = []
var _jobs := {}      # task id → key
var _trade_w: Array = []
var stats := {"near": 0, "far": 0, "pending": 0, "built": 0, "last_ms": 0.0, "max_upload_ms": 0.0}
var focus := Vector2.ZERO
var max_jobs := 2
var _wanted := 0
var street: StreetDetail

func setup(p: CityPack, sp: SignPainter) -> void:
	pack = p
	# warm shared resources on the main thread before workers touch them
	Mats.facade(); Mats.generic(); Props.foliage_mat(); StreetDetail.poster_mat(); StreetDetail.kolam_mat()
	for m in ["tree_rain", "tree_neem", "tree_gulmohar", "tree_young", "palm", "palm_short", "shrub", "pole", "pole_lamp", "lamp_post", "transformer", "bike_parked", "scooter_parked", "crate", "stool", "cylinder", "drum", "sack", "bin", "stand"]:
		Props.get_mesh(m)
	painter = sp
	street = StreetDetail.new(p)
	near_r = Settings.q("near_r")
	far_r = Settings.q("far_r")
	if Settings.has_arg("near"): near_r = Settings.arg_f("near")
	if Settings.has_arg("far"): far_r = Settings.arg_f("far")
	max_jobs = maxi(1, OS.get_processor_count() - 2)
	for t in pack.names.trades: _trade_w.append(t.w)
	for key in pack.region.chunks:
		var p2: PackedStringArray = String(key).split("_")
		chunks[key] = {"key": key, "cx": int(p2[0]), "cz": int(p2[1]), "center": pack.chunk_center(key), "state": "none", "pending": "", "node": null, "shops": [], "lights": PackedFloat32Array()}

func is_idle() -> bool:
	return _wanted == 0 and _jobs.is_empty() and _done.is_empty() and not painter.busy

func _process(_dt: float) -> void:
	update_focus(focus)

func update_focus(f: Vector2) -> void:
	var want: Array = []
	var cs := pack.chunk_size
	for c in chunks.values():
		var d: float = f.distance_to(c.center) - cs * 0.5
		var target := "near" if d < near_r else ("far" if d < far_r else "none")
		if c.state == "near" and target != "near" and d < near_r + 60.0: target = "near"
		if c.state == "far" and target == "none" and d < far_r + 120.0: target = "far"
		if target == "none":
			if c.state != "none": _unload(c)
			continue
		if c.state != target and c.pending != target:
			want.append([d * (0.6 if target == "near" else 1.0), c.key, target])
	want.sort_custom(func(a, b): return a[0] < b[0])
	_wanted = want.size()
	for w in want:
		if _jobs.size() >= max_jobs: break
		var c: Dictionary = chunks[w[1]]
		if c.pending != "": continue
		c.pending = w[2]
		var key: String = w[1]
		var detail: bool = w[2] == "near"
		var id := WorkerThreadPool.add_task(_job.bind(key, detail), true, "chunk " + key)
		_jobs[id] = key
	# collect finished tasks
	for id in _jobs.keys():
		if WorkerThreadPool.is_task_completed(id):
			WorkerThreadPool.wait_for_task_completion(id)
			_jobs.erase(id)
	# upload at most one chunk per frame (hitch budget)
	_mutex.lock()
	var res = _done.pop_front() if not _done.is_empty() else null
	_mutex.unlock()
	if res != null: _upload(res)
	stats.pending = _jobs.size() + _done.size()

func _job(key: String, detail: bool) -> void:
	var t0 := Time.get_ticks_usec()
	var bs := pack.load_chunk(key)
	var ctx := BuildingGen.Ctx.new()
	ctx.detail = detail
	ctx.style = pack.style
	ctx.trade_w = _trade_w
	for b in bs: BuildingGen.gen(b, ctx)
	var col := PackedVector3Array()
	if detail:
		for c in ctx.colliders: col.append_array(_shell_tris(c.f, c.h))
		street.build_chunk(key, chunks[key].center, ctx)
	var out := {"key": key, "detail": detail, "ctx": ctx, "col": col}
	out["node"] = _build_node(out)
	out["ms"] = (Time.get_ticks_usec() - t0) / 1000.0
	if Settings.has_arg("prof"): print("[chunk] %s %s %d bldg %.0f ms" % [key, "near" if detail else "far", bs.size(), out.ms])
	_mutex.lock()
	_done.append(out)
	_mutex.unlock()

static func _shell_tris(P: PackedVector2Array, h: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	var n := P.size()
	for i in n:
		var a := P[i]; var b := P[(i + 1) % n]
		out.append_array([Vector3(a.x, 0, a.y), Vector3(b.x, 0, b.y), Vector3(b.x, h, b.y), Vector3(a.x, 0, a.y), Vector3(b.x, h, b.y), Vector3(a.x, h, a.y)])
	var tris := Geometry2D.triangulate_polygon(P)
	for i in range(0, tris.size(), 3):
		out.append_array([Vector3(P[tris[i]].x, h, P[tris[i]].y), Vector3(P[tris[i + 1]].x, h, P[tris[i + 1]].y), Vector3(P[tris[i + 2]].x, h, P[tris[i + 2]].y)])
	return out

## builds the chunk's node tree off the main thread (meshes, multimeshes, collision shapes);
## the RenderingServer/PhysicsServer are thread-safe in Godot 4, nodes are not yet in the tree.
func _build_node(res: Dictionary) -> Node3D:
	var ctx: BuildingGen.Ctx = res.ctx
	var node := Node3D.new()
	node.name = "chunk_" + res.key
	var shadows := GeometryInstance3D.SHADOW_CASTING_SETTING_ON if res.detail and Settings.q("shadows") else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for pair in [[ctx.facade, Mats.facade()], [ctx.generic, Mats.generic()]]:
		var mb: MB = pair[0]
		if mb.count() == 0: continue
		var mi := MeshInstance3D.new()
		mi.mesh = mb.to_mesh(pair[1])
		mi.cast_shadow = shadows
		if not res.detail: mi.visibility_range_end = far_r + 200.0
		node.add_child(mi)
	if res.detail:
		if res.col.size() > 0:
			var body := StaticBody3D.new()
			var shape := ConcavePolygonShape3D.new()
			shape.backface_collision = true
			shape.set_faces(res.col)
			var cs := CollisionShape3D.new()
			cs.shape = shape
			body.add_child(cs)
			node.add_child(body)
		street.attach_chunk(node, ctx)
		if ctx.sign.count() > 0:
			var smi := MeshInstance3D.new()
			smi.name = "signs"
			smi.mesh = ctx.sign.to_mesh()
			smi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			smi.visible = false
			node.add_child(smi)
	return node

func _upload(res: Dictionary) -> void:
	var t0 := Time.get_ticks_usec()
	var c: Dictionary = chunks[res.key]
	var want: String = c.pending
	c.pending = ""
	var node: Node3D = res.node
	if want == "" or (want == "near") != res.detail:
		node.free()
		return # superseded
	_unload(c)
	var ctx: BuildingGen.Ctx = res.ctx
	add_child(node)
	if res.detail:
		if ctx.sign.count() > 0: _paint_signs(c, node, ctx)
		c.shops = ctx.shops
		c.lights = ctx.lights
	c.node = node
	c.state = want
	stats.built += 1
	stats.last_ms = res.ms
	stats.max_upload_ms = maxf(stats.max_upload_ms, (Time.get_ticks_usec() - t0) / 1000.0)
	_count()
	if want == "near": chunk_near.emit(c.key, c)

func _paint_signs(c: Dictionary, node: Node3D, ctx: BuildingGen.Ctx) -> void:
	var tex := await painter.paint(ctx.signs)
	if not is_instance_valid(node) or c.node != node: return
	var rows := maxi(1, ceili(ctx.signs.size() / float(BuildingGen.SIGN_COLS)))
	var mi: MeshInstance3D = node.get_node_or_null("signs")
	if mi == null: return
	mi.material_override = Mats.sign(tex, rows)
	mi.visible = true

func _unload(c: Dictionary) -> void:
	if c.node:
		if c.state == "near": chunk_unloaded.emit(c.key, c)
		c.node.queue_free()
		c.node = null
	c.state = "none"
	_count()

func _count() -> void:
	var nn := 0; var ff := 0
	for c in chunks.values():
		if c.state == "near": nn += 1
		elif c.state == "far": ff += 1
	stats.near = nn; stats.far = ff
