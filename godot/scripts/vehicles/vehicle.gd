class_name Vehicle
extends RigidBody3D
## Raycast vehicle (arcade-realistic) for autos, bikes and cars. Each wheel is a suspension ray
## with a spring-damper, tyre forces from slip with a friction circle, drive and brakes.
## Autos are tippy (high centre of mass, narrow track); bikes balance with a lean controller that
## leans into turns. Forward is -Z (Godot convention).

var def: Dictionary
var wheels: Array = []        # {mount, radius, steer, drive, rest, k, c, comp, mesh, spin, contact}
var driver: Node = null
var throttle := 0.0
var brake := 0.0
var steer := 0.0
var handbrake := false
var steer_angle := 0.0
var cam_height := 2.2
var cam_dist := 6.0
var exit_left := false
var kind := "car"
var wheelbase := 2.4
var speed_kmh := 0.0
var horn_t := 0.0
var _visual: Node3D
var ai_drive: Callable    # optional autopilot (harness drive test)

func setup(d: Dictionary) -> void:
	def = d
	kind = d.kind
	mass = d.mass
	cam_height = d.get("cam_height", 2.2)
	cam_dist = d.get("cam_dist", 6.0)
	exit_left = d.get("exit_left", false)
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = d.com
	continuous_cd = true
	can_sleep = false
	linear_damp = 0.02
	angular_damp = d.get("ang_damp", 0.6)
	add_to_group("vehicles")
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = d.hull_size
	cs.shape = box
	cs.position = d.hull_pos
	add_child(cs)
	var pm := PhysicsMaterial.new()
	pm.friction = 0.6
	pm.bounce = 0.05
	physics_material_override = pm
	_visual = Node3D.new()
	add_child(_visual)
	var mi := MeshInstance3D.new()
	mi.mesh = d.mesh
	_visual.add_child(mi)
	var zs: Array[float] = []
	for w in d.wheels:
		var wm := MeshInstance3D.new()
		wm.mesh = d.wheel_mesh
		wm.scale = Vector3.ONE * (w.r / 0.3)
		_visual.add_child(wm)
		wheels.append({"mount": w.p, "radius": w.r, "steer": w.get("steer", false), "drive": w.get("drive", false), "rest": d.susp_rest,
			"k": d.susp_k, "c": d.susp_c, "comp": 0.0, "mesh": wm, "spin": 0.0, "contact": false})
		zs.append(w.p.z)
	wheelbase = maxf(0.5, zs.max() - zs.min())

func get_exclusions() -> Array:
	return [get_rid()]

func head_position() -> Vector3:
	return global_transform * def.get("head", Vector3(0, 1.5, 0.2))

func enter(p: Node) -> void:
	driver = p

func _physics_process(dt: float) -> void:
	if ai_drive.is_valid():
		ai_drive.call(self, dt)
	elif driver:
		throttle = maxf(Input.get_action_strength("move_forward"), Input.get_action_strength("throttle"))
		brake = maxf(Input.get_action_strength("move_back"), Input.get_action_strength("brake"))
		steer = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
		handbrake = Input.is_action_pressed("handbrake")
		if Input.is_action_just_pressed("interact") and speed_kmh < 12.0:
			var p = driver
			driver = null
			p.exit_vehicle()
	else:
		throttle = 0.0; brake = 0.3; steer = 0.0
	_drive(dt)

func _drive(dt: float) -> void:
	var space := get_world_3d().direct_space_state
	var up := global_basis.y
	var fwd := -global_basis.z
	var v := linear_velocity
	var v_fwd := v.dot(fwd)
	speed_kmh = absf(v_fwd) * 3.6
	# steering: less lock at speed, smooth
	var max_steer: float = def.max_steer * lerpf(1.0, 0.35, clampf(absf(v_fwd) / 25.0, 0.0, 1.0))
	steer_angle = move_toward(steer_angle, -steer * max_steer, dt * def.steer_speed)
	var reversing := brake > 0.1 and v_fwd < 1.0 and throttle < 0.1
	var n_drive := 0
	for w in wheels: if w.drive: n_drive += 1
	var com_g := global_transform * center_of_mass
	var any_contact := false
	for w in wheels:
		var mount: Vector3 = global_transform * w.mount
		var len: float = w.rest + w.radius
		var q := PhysicsRayQueryParameters3D.create(mount, mount - up * len)
		q.exclude = [get_rid()]
		var hit := space.intersect_ray(q)
		var wheel_center: Vector3 = mount - up * w.rest
		w.contact = not hit.is_empty()
		if w.contact:
			any_contact = true
			var dist: float = mount.distance_to(hit.position)
			var comp: float = len - dist
			var comp_v: float = (comp - w.comp) / dt
			w.comp = comp
			var fn := maxf(0.0, w.k * comp + w.c * comp_v)
			var nrm: Vector3 = hit.normal
			var cp: Vector3 = hit.position
			apply_force(nrm * fn, cp - global_position)
			# tyre frame
			var wf: Vector3 = fwd.rotated(up, steer_angle) if w.steer else fwd
			wf = (wf - nrm * wf.dot(nrm)).normalized()
			var wr := wf.cross(nrm).normalized()
			var pv := linear_velocity + angular_velocity.cross(cp - com_g)
			var v_long := pv.dot(wf)
			var v_lat := pv.dot(wr)
			var mu: float = def.grip
			var f_lat: float = -v_lat * def.lat_stiff * fn
			if handbrake and not w.steer: f_lat *= 0.35
			var f_long := 0.0
			if w.drive:
				var top: float = def.top_speed
				var power_f: float = def.engine * (1.0 - clampf(v_fwd / top, 0.0, 1.0) ** 2)
				if reversing: f_long -= def.engine * 0.5 * brake * (1.0 if v_fwd > -def.top_speed * 0.25 else 0.0) / n_drive
				else: f_long += throttle * power_f / n_drive
			if brake > 0.0 and not reversing and v_long > 0.3:
				f_long -= brake * def.brake * fn
			if handbrake and not w.steer:
				f_long -= signf(v_long) * mu * fn * 0.8
			f_long -= v_long * def.roll_res * fn * 0.01
			# friction circle
			var f2 := Vector2(f_long, f_lat)
			var lim := mu * fn
			if f2.length() > lim: f2 = f2.normalized() * lim
			apply_force(wf * f2.x + wr * f2.y, cp - global_position)
			wheel_center = mount - up * (dist - w.radius)
			w.spin += v_long / w.radius * dt
		else:
			w.comp = 0.0
			if w.drive: w.spin += throttle * dt * 20.0
		# visuals
		var wm: MeshInstance3D = w.mesh
		wm.global_position = wheel_center
		var yaw_off := steer_angle if w.steer else 0.0
		wm.global_basis = global_basis * Basis(Vector3.UP, yaw_off) * Basis(Vector3.RIGHT, -w.spin)
	# aerodynamic drag
	apply_central_force(-v * v.length() * def.drag)
	# two-wheeler balance: lean into turns, stay upright when slow (rider's feet)
	if kind == "bike":
		var lean_target := 0.0
		if absf(v_fwd) > 1.0:
			var curv := tan(steer_angle) / wheelbase
			lean_target = clampf(atan(v_fwd * v_fwd * curv / 9.81), -0.75, 0.75)
		var right := global_basis.x
		var cur := asin(clampf(right.y, -1.0, 1.0))
		var rate := angular_velocity.dot(fwd)
		var tq: float = (-(lean_target - cur) * def.lean_kp - rate * def.lean_kd) * mass
		apply_torque(fwd * tq)
	# keep autos and cars from staying on their roof forever: self-right slowly when nearly stopped
	if not any_contact and up.y < 0.3 and linear_velocity.length() < 1.0:
		apply_torque(up.cross(Vector3.UP) * mass * 6.0)
	if Input.is_action_pressed("horn") and driver: horn_t = 0.3
