class_name Harness
extends Node
## Verification harness. `godot --path godot -- --shot=<set> [--only=name] [--quality=…]` renders
## each shot of the set in godot/harness/shots.json from a fixed camera, waits for streaming to
## settle, saves docs/screens/<set>/<name>.png plus report.json (frame stats), then quits.
## Shots may also run scripted tests ("test": "drive" / "walk") that record hitch statistics.

var game: Node
var cam: Camera3D
var report := {}
var out_dir: String

func start(g: Node) -> void:
	game = g
	var set_name := Settings.arg("shot")
	var sets = CityPack.load_json("res://harness/shots.json")
	var shots: Array = sets.get(set_name, [])
	if shots.is_empty():
		push_error("unknown shot set " + set_name)
		get_tree().quit(1)
		return
	out_dir = ProjectSettings.globalize_path("res://").path_join("../docs/screens/" + set_name)
	DirAccess.make_dir_recursive_absolute(out_dir)
	cam = Camera3D.new()
	cam.fov = Settings.get_v("fov")
	cam.far = 4000.0
	cam.near = 0.1
	game.add_child(cam)
	cam.make_current()
	_run(shots)

func _run(shots: Array) -> void:
	var only := Settings.arg("only")
	for s in shots:
		if only != "" and not (s.name in only.split(",")): continue
		var t0 := Time.get_ticks_msec()
		var w: World = game.world
		if s.has("hour"): w.clock.hour = float(s.hour)
		w.clock.paused = true
		w.clock.wet = float(s.get("wet", 0.0))
		var c: Array = s.cam
		cam.position = Vector3(c[0], c[1], c[2])
		var target := Vector3(c[3], c[4], c[5])
		if s.get("snap", false):
			# put the camera on the nearest road (offset toward one side) and look along it
			var rr := w.pack.nearest_road(c[0], c[2], 80.0, int(s.get("min_rank", 1)))
			if not rr.is_empty():
				var dir: Vector2 = rr.dir
				var side: Vector2 = Vector2(-dir.y, dir.x) * float(s.get("side", 0.0)) * float(rr.w) * 0.5
				var pp: Vector2 = rr.p + side
				cam.position = Vector3(pp.x, c[1], pp.y)
				var fwd: Vector2 = dir * (1.0 if (Vector2(c[3], c[5]) - pp).dot(dir) >= 0.0 else -1.0)
				target = Vector3(pp.x + fwd.x * 40.0, c[4], pp.y + fwd.y * 40.0)
		cam.look_at(target, Vector3.UP)
		if s.has("fov"): cam.fov = float(s.fov)
		w.set_focus(cam.position)
		if s.has("test"):
			await _test(s, w)
			continue
		# wait for streaming to settle (all near chunks built and signs painted)
		var frames := 0
		while frames < 3000:
			await get_tree().process_frame
			frames += 1
			if frames % 25 == 0:
				print("[harness] wait f%d rss %.0f nodes %d near %d crowd_near %s traffic %s" % [frames, rss_mb(), Performance.get_monitor(Performance.OBJECT_NODE_COUNT), w.streamer.stats.near, w.crowd.stats.near if w.crowd else -1, w.traffic.stats if w.traffic else {}])
			if frames > 10 and w.streamer.is_idle(): break
		print("[harness] streamed: rss %.0f MB" % rss_mb())
		# populate the crowd around the camera before the shot (fast-forward the sim a few seconds)
		if w.traffic:
			w.traffic.focus = cam.position
			w.traffic.clear()
			w.traffic.populate(w.clock.hour)
			for k in 30: w.traffic.update(0.2, w.clock.hour)
		print("[harness] traffic: rss %.0f MB" % rss_mb())
		if w.crowd:
			w.crowd.focus = cam.position
			for k in 40: w.crowd.update(0.25, w.clock.hour)
		print("[harness] crowd: rss %.0f MB" % rss_mb())
		for i in int(s.get("settle", 12)): await get_tree().process_frame
		var stats := _frame_stats()
		stats["npcs"] = w.crowd.stats.agents if w.crowd else 0
		stats["traffic"] = w.traffic.stats.agents if w.traffic else 0
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var path := out_dir.path_join(s.name + ".png")
		img.save_png(path)
		stats["wait_frames"] = frames
		stats["wall_ms"] = Time.get_ticks_msec() - t0
		report[s.name] = stats
		print("[harness] %s → %s (%d frames, %d ms)" % [s.name, path, frames, stats.wall_ms])
	var f := FileAccess.open(out_dir.path_join("report.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "  "))
	f.close()
	get_tree().quit()

## scripted tests: "scene" (player + parked vehicles seen through the game camera) and
## "drive" (autopilot drives a vehicle across streamed chunks; records hitches and streaming)
func _test(s: Dictionary, w: World) -> void:
	var t0 := Time.get_ticks_msec()
	var c: Array = s.cam
	var rr := w.pack.nearest_road(c[0], c[2], 120.0, 2)
	var p := Vector3(c[0], 0.3, c[2])
	if not rr.is_empty(): p = Vector3(rr.p.x, 0.3, rr.p.y)
	game.call("_spawn_player_at", p)
	var player: Node3D = game.player
	var rig: CameraRig = game.cam_rig
	rig.mode = s.get("cam_mode", "third")
	if not rr.is_empty(): player.rotation.y = atan2(-rr.dir.x, -rr.dir.y)
	rig.yaw = player.rotation.y + float(s.get("yaw_off", 0.0))
	rig.pitch = float(s.get("pitch", -0.2))
	cam.clear_current(false)
	rig.cam.current = true
	rig.cam.make_current()
	var stats := {}
	var veh: Vehicle = null
	if s.test == "drive":
		veh = VehicleSpawner.make(s.get("vehicle", "auto"), 4242)
		game.add_child(veh)
		veh.global_position = p + Vector3(0, 0.4, 0)
		veh.rotation.y = player.rotation.y
		var ap := Autopilot.new(w.pack, 11)
		ap.target_speed = float(s.get("speed", 9.0))
		veh.ai_drive = ap.drive
		player.call("_enter", veh)
		var secs := float(s.get("seconds", 60.0))
		var sim := 0.0
		var frames := 0
		var max_up := 0.0
		var built0: int = w.streamer.stats.built
		var worst_dt := 0.0
		var flips := 0
		RenderingServer.render_loop_enabled = not Settings.has_arg("norender_sim") and false
		while sim < secs:
			await get_tree().physics_frame
			sim += 1.0 / Engine.physics_ticks_per_second
			frames += 1
			w.set_focus(veh.global_position)
			worst_dt = maxf(worst_dt, get_process_delta_time())
			if veh.global_basis.y.y < 0.3: flips += 1
		RenderingServer.render_loop_enabled = true
		stats = {"distance_m": ap.distance, "sim_s": sim, "chunks_built": w.streamer.stats.built - built0,
			"max_upload_ms": w.streamer.stats.max_upload_ms, "flipped_frames": flips, "end": [veh.global_position.x, veh.global_position.z]}
	else:
		VehicleSpawner.spawn_demo(game, w, p)
	var frames2 := 0
	while frames2 < 2000:
		await get_tree().process_frame
		frames2 += 1
		w.set_focus(player.global_position if veh == null else veh.global_position)
		if frames2 > 20 and w.streamer.is_idle(): break
	for i in int(s.get("settle", 30)): await get_tree().process_frame
	stats.merge(_frame_stats())
	stats["cam_dot"] = (-rig.cam.global_basis.z).dot((player.global_position + Vector3(0, 1, 0) - rig.cam.global_position).normalized())
	stats["pdbg"] = [player.visible, player.is_visible_in_tree(), player.get_child_count(), player.get("body") != null and player.body.get_child_count(), player.get_script().resource_path]
	stats["current_cam"] = str(get_viewport().get_camera_3d().get_path())
	stats["player"] = [player.global_position.x, player.global_position.y, player.global_position.z]
	stats["cam"] = [rig.cam.global_position.x, rig.cam.global_position.y, rig.cam.global_position.z]
	await RenderingServer.frame_post_draw
	var path := out_dir.path_join(s.name + ".png")
	get_viewport().get_texture().get_image().save_png(path)
	stats["wall_ms"] = Time.get_ticks_msec() - t0
	report[s.name] = stats
	print("[harness] %s → %s %s" % [s.name, path, JSON.stringify(stats)])
	if veh: veh.queue_free()

static func rss_mb() -> float:
	var f := FileAccess.open("/proc/self/status", FileAccess.READ)
	if f == null: return 0.0
	for i in 80:
		var l := f.get_line()
		if l.begins_with("VmRSS"): return float(l.split(":")[1].strip_edges().split(" ")[0]) / 1024.0
	return 0.0

func _frame_stats() -> Dictionary:
	var w: World = game.world
	return {
		"rss_mb": rss_mb(),
		"fps": Engine.get_frames_per_second(),
		"draw_calls": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		"primitives": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
		"objects": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
		"video_mem_mb": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0,
		"static_mem_mb": OS.get_static_memory_usage() / 1048576.0,
		"chunks_near": w.streamer.stats.near, "chunks_far": w.streamer.stats.far,
		"chunk_gen_ms": w.streamer.stats.last_ms, "max_upload_ms": w.streamer.stats.max_upload_ms,
		"adapter": RenderingServer.get_video_adapter_name(),
	}
