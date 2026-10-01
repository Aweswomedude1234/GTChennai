extends Node3D
## Asset studio: renders people / vehicles on a neutral turntable for review.
## `godot --path godot res://scenes/studio.tscn -- --studio=human,auto,bike,car --out=docs/screens/studio`
## Each subject is rendered from 3 angles into one contact image.

func _ready() -> void:
	var subjects := Settings.arg("studio", "human,auto,bike,car").split(",")
	var out := ProjectSettings.globalize_path("res://").path_join("../" + Settings.arg("out", "docs/screens/studio"))
	DirAccess.make_dir_recursive_absolute(out)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.42, 0.44, 0.46)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.78, 0.82)
	e.ambient_light_energy = 0.6
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	e.ssao_enabled = true
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.light_energy = 2.2
	sun.shadow_enabled = true
	add_child(sun)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new(); pm.size = Vector2(30, 30)
	floor_mi.mesh = pm
	var fm := StandardMaterial3D.new(); fm.albedo_color = Color(0.5, 0.49, 0.47)
	floor_mi.material_override = fm
	add_child(floor_mi)
	var cam := Camera3D.new()
	cam.fov = 35
	add_child(cam)
	cam.make_current()
	for s in subjects:
		var node: Node3D
		var size := 2.0
		match s:
			"human", "humans":
				node = Node3D.new()
				for i in 6:
					var h := ProcHuman.new()
					h.build(Appearance.make(Rng.new(100 + i * 31)))
					h.position = Vector3((i - 2.5) * 0.8, 0, 0)
					node.add_child(h)
				size = 5.0
			"auto", "bike", "car":
				var d: Dictionary = VehicleDefs.auto_rickshaw(5) if s == "auto" else (VehicleDefs.bike(5) if s == "bike" else VehicleDefs.car(5))
				node = Node3D.new()
				var mi := MeshInstance3D.new(); mi.mesh = d.mesh; node.add_child(mi)
				for w in d.wheels:
					var wm := MeshInstance3D.new(); wm.mesh = d.wheel_mesh; wm.scale = Vector3.ONE * (w.r / 0.3)
					wm.position = Vector3(w.p.x, w.r, w.p.z); node.add_child(wm)
				size = 4.5 if s == "car" else 3.2
		add_child(node)
		var imgs: Array[Image] = []
		for ang in [-0.6, 0.6, 2.6]:
			var dir := Vector3(sin(ang), 0.35, cos(ang)).normalized()
			cam.position = Vector3(0, 0.8, 0) + dir * size * 2.2
			cam.look_at(Vector3(0, 0.8, 0))
			for i in 4: await get_tree().process_frame
			await RenderingServer.frame_post_draw
			imgs.append(get_viewport().get_texture().get_image())
		var w0 := imgs[0].get_width(); var h0 := imgs[0].get_height()
		var sheet := Image.create(w0 * 3, h0, false, imgs[0].get_format())
		for i in 3: sheet.blit_rect(imgs[i], Rect2i(0, 0, w0, h0), Vector2i(w0 * i, 0))
		sheet.save_png(out.path_join(s + ".png"))
		print("[studio] ", s)
		node.queue_free()
		await get_tree().process_frame
	get_tree().quit()
