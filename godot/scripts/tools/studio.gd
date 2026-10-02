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
		var ty := 0.8
		match s:
			"human", "humans":
				node = Node3D.new()
				for i in 6:
					var h := ProcHuman.new()
					h.build(Appearance.make(Rng.new(100 + i * 31)))
					h.position = Vector3((i - 2.5) * 0.8, 0, 0)
					node.add_child(h)
				size = 5.0
			"mpfb":
				node = Node3D.new()
				var files := DirAccess.get_files_at("res://assets/humans")
				var i := 0
				for f in files:
					if not f.ends_with(".glb"): continue
					var sc: PackedScene = load("res://assets/humans/" + f)
					var inst := sc.instantiate()
					inst.position = Vector3((i - 1.5) * 0.9, 0, 0)
					node.add_child(inst)
					i += 1
					if i >= 6: break
				size = 2.2
			"actors":
				node = Node3D.new()
				var clips := ["walk", "talk", "drink_tea", "idle", "traffic_police", "argue", "jog", "idle_alt"]
				var specs := HumanActor.specs()
				for i in 8:
					var a := HumanActor.new()
					node.add_child(a)
					a.build(specs[(i * 3) % specs.size()], null, 50 + i)
					a.position = Vector3((i % 4 - 1.5) * 1.1, 0, (i / 4) * 1.6 - 0.8)
					a.player.play(clips[i])
					a.player.seek(1.0 + i * 0.37, true)
				size = 2.6
			"faces":
				node = Node3D.new()
				var specs := HumanActor.specs()
				for i in 3:
					var a := HumanActor.new()
					node.add_child(a)
					a.build(specs[[0, 9, 4][i]], null, 70 + i)
					a.position = Vector3((i - 1) * 0.45, 0, 0)
					a.player.play("idle")
					a.player.seek(0.5, true)
				size = 0.42
				ty = 1.5
			"v_auto", "v_hatch", "v_bike", "v_scooter", "v_bus":
				var vid := s.substr(2)
				node = Node3D.new()
				node.add_child(VehicleModel.make(vid, 3))
				size = {"auto": 2.6, "hatch": 3.4, "bike": 2.0, "scooter": 1.9, "bus": 9.0}[vid]
				ty = {"bus": 1.6, "hatch": 0.7, "auto": 0.9}.get(vid, 0.6)
			"riders":
				node = Node3D.new()
				var specs := HumanActor.specs()
				var setups := [["bike", ["ride_bike", "ride_pillion"]], ["scooter", ["ride_scooter"]], ["auto", ["ride_auto", "ride_pass", "ride_pass"]]]
				for i in setups.size():
					var vm := VehicleModel.make(setups[i][0], 21 + i)
					vm.position = Vector3((i - 1) * 2.0, 0, 0)
					node.add_child(vm)
					var clips_: Array = setups[i][1]
					for k in clips_.size():
						var a := HumanActor.new()
						vm.add_child(a)
						a.build(specs[(i * 5 + k * 3) % specs.size()], null, 40 + i * 7 + k)
						a.ride(clips_[k], 0.0 if clips_[k] != "ride_pass" else (0.28 if k == 1 else -0.28))
				size = 2.8
				ty = 0.9
			"fleet":
				node = Node3D.new()
				var x := -9.0
				var k := 0
				for f in ["bus_0", "hatch_0", "hatch_2", "auto_0", "auto_1", "bike_0", "scooter_1"]:
					k += 1
					var inst: Node3D = VehicleModel.make(f.split("_")[0], 11 + k * 7)
					var wdt := 2.6 if f.begins_with("bus") else (1.7 if f.begins_with("hatch") else (1.4 if f.begins_with("auto") else 0.8))
					x += wdt * 0.5 + 0.4
					inst.position = Vector3(x, 0, 0)
					x += wdt * 0.5
					node.add_child(inst)
				size = 7.0
				ty = 1.0
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
		for ang in ([-0.25, 0.0, 0.5] if s == "faces" else [-0.6, 0.6, 2.6]):
			var dir := Vector3(sin(ang), 0.35 if s != "faces" else 0.05, cos(ang) * (-1.0 if s in ["faces", "actors"] else 1.0)).normalized()
			cam.position = Vector3(0, ty, 0) + dir * size * 2.2
			cam.look_at(Vector3(0, ty, 0))
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
