class_name World
extends Node3D
## The playable world for one city pack: region geometry, streamed chunks, sky/clock and physics.

var pack: CityPack
var region: RegionBuilder
var streamer: Streamer
var clock: SkyClock
var painter: SignPainter

func setup(city: String) -> void:
	var t0 := Time.get_ticks_msec()
	pack = CityPack.new(city)
	clock = SkyClock.new()
	clock.name = "SkyClock"
	add_child(clock)
	painter = SignPainter.new()
	painter.names = pack.names
	painter.road_names = pack.road_names
	add_child(painter)
	_init_posters()
	region = RegionBuilder.new(pack)
	region.build()
	_add_mesh("ground", region.ground, Mats.ground(), false)
	_add_mesh("roads", region.roads, Mats.road(), false)
	_add_mesh("walks", region.walks, Mats.generic(), true)
	_add_mesh("tank_water", region.water, Mats.water(), false)
	_add_mesh("sea", region.sea, Mats.sea(), false)
	_add_mesh("landmarks", region.landmarks.mb, Mats.generic(), true)
	# static colliders: ground (incl. beach slope), tank steps, kerbs and footpaths
	var body := StaticBody3D.new()
	body.name = "RegionCollider"
	add_child(body)
	var ground_tris := PackedVector3Array()
	var g := region.ground
	for i in range(0, g.idx.size(), 3):
		var a := g.v[g.idx[i]]
		if a.y > 0.011: continue   # skip area overlays (same plane)
		ground_tris.append_array([a, g.v[g.idx[i + 1]], g.v[g.idx[i + 2]]])
	for faces in [ground_tris, region.tank_colliders, region.kerb_colliders, region.landmarks.colliders]:
		if faces.is_empty(): continue
		var sh := ConcavePolygonShape3D.new()
		sh.backface_collision = true
		sh.set_faces(faces)
		var cs := CollisionShape3D.new()
		cs.shape = sh
		body.add_child(cs)
	streamer = Streamer.new()
	streamer.name = "Streamer"
	add_child(streamer)
	streamer.setup(pack, painter)
	_build_horizon()
	if not Settings.has_arg("nocrowd"):
		crowd = Crowd.new()
		crowd.name = "Crowd"
		add_child(crowd)
		crowd.setup(pack)
	if not Settings.has_arg("notraffic"):
		traffic = Traffic.new()
		traffic.name = "Traffic"
		add_child(traffic)
		traffic.setup(pack)
	print("[world] region built in %d ms (%d road verts, %d ground verts)" % [Time.get_ticks_msec() - t0, region.roads.count(), region.ground.count()])

func _add_mesh(nm: String, mb: MB, mat: Material, shadows: bool) -> void:
	if mb.count() == 0: return
	var mi := MeshInstance3D.new()
	mi.name = nm
	mi.mesh = mb.to_mesh(mat)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

func set_focus(p: Vector3) -> void:
	streamer.focus = Vector2(p.x, p.z)
	clock.focus = p

func _init_posters() -> void:
	await get_tree().process_frame
	StreetDetail.poster_atlas = await PosterPainter.paint(painter)
	StreetDetail.poster_mat()

var horizon: HorizonCity
var horizon_nodes := {}

func _build_horizon() -> void:
	horizon = HorizonCity.new(pack)
	var id := WorkerThreadPool.add_task(horizon.build, true, "horizon city")
	while not WorkerThreadPool.is_task_completed(id): await get_tree().process_frame
	WorkerThreadPool.wait_for_task_completion(id)
	var root := Node3D.new()
	root.name = "Horizon"
	add_child(root)
	for key in horizon.chunk_meshes:
		var mi := MeshInstance3D.new()
		mi.mesh = horizon.chunk_meshes[key]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = streamer.chunks[key].state == "none" if streamer.chunks.has(key) else true
		root.add_child(mi)
		horizon_nodes[key] = mi
	var ring := MeshInstance3D.new()
	ring.mesh = horizon.ring_mesh
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ring)
	streamer.horizon_nodes = horizon_nodes
	horizon_ready = true

var horizon_ready := false

var crowd: Crowd
var traffic: Traffic
var obstacles: Array[Vector3] = []   # set by the game: player / player's vehicle

func _process(dt: float) -> void:
	if crowd:
		crowd.focus = Vector3(streamer.focus.x, 0, streamer.focus.y)
		crowd.update(dt, clock.hour)
	if traffic:
		traffic.focus = Vector3(streamer.focus.x, 0, streamer.focus.y)
		traffic.obstacles = obstacles
		traffic.update(dt, clock.hour)
