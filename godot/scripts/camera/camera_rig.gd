class_name CameraRig
extends Node3D
## Three camera modes (BRIEF §12): third-person orbit (default), first-person, and classic top-down.
## In vehicles the third-person camera becomes a lagged chase camera. Switch with C / Back,
## or set `camera` in settings. Uses a SpringArm3D so the camera never clips into buildings.

const MODES := ["third", "first", "top"]
var mode := "third"
var target: Node3D            # player or vehicle
var yaw := 0.0
var pitch := -0.25
var cam: Camera3D
var arm: SpringArm3D
var pivot: Node3D
var _chase_yaw := 0.0
var _top_h := 30.0
var _shake := 0.0

func _ready() -> void:
	mode = Settings.get_v("camera")
	pivot = Node3D.new()
	add_child(pivot)
	arm = SpringArm3D.new()
	arm.spring_length = 4.0
	arm.margin = 0.25
	var probe := SphereShape3D.new()
	probe.radius = 0.25
	arm.shape = probe
	pivot.add_child(arm)
	cam = Camera3D.new()
	cam.fov = Settings.get_v("fov")
	cam.near = 0.08
	cam.far = 9000.0
	arm.add_child(cam)
	cam.make_current()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func follow(t: Node3D) -> void:
	target = t
	if t: yaw = t.global_rotation.y
	if t and t.has_method("get_exclusions"):
		arm.clear_excluded_objects()
		for rid in t.get_exclusions(): arm.add_excluded_object(rid)

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var s: float = Settings.get_v("mouse_sens")
		yaw -= e.relative.x * s
		pitch -= e.relative.y * s * (-1.0 if Settings.get_v("invert_y") else 1.0)
		pitch = clampf(pitch, -1.35, 1.0 if mode == "first" else 0.6)
	if e.is_action_pressed("camera_cycle"):
		mode = MODES[(MODES.find(mode) + 1) % MODES.size()]
		Settings.set_v("camera", mode)

func in_vehicle() -> bool:
	return target != null and target.is_in_group("vehicles")

## forward direction for movement input on foot (xz plane)
func move_basis() -> Basis:
	if mode == "top": return Basis()
	return Basis(Vector3.UP, yaw)

func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)

func _process(dt: float) -> void:
	if target == null: return
	var look := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	yaw -= look.x * dt * 2.4
	pitch = clampf(pitch - look.y * dt * 1.6, -1.35, 0.6)
	var tp := target.global_position
	var veh := in_vehicle()
	match mode:
		"third":
			var h := 1.55
			var dist := 3.6
			if veh:
				h = target.get("cam_height") if target.get("cam_height") else 2.2
				dist = target.get("cam_dist") if target.get("cam_dist") else 6.0
				# lagged chase behind the vehicle unless the player is looking around
				var vy: float = target.global_rotation.y
				var spd: float = target.linear_velocity.length() if target is RigidBody3D else 0.0
				if look.length() < 0.1 and spd > 2.0:
					_chase_yaw = lerp_angle(_chase_yaw, vy, clampf(dt * 2.5, 0.0, 1.0))
					yaw = lerp_angle(yaw, _chase_yaw, clampf(dt * 1.8, 0.0, 1.0))
				else:
					_chase_yaw = yaw
				if Input.is_action_pressed("look_back"): yaw = vy + PI
				dist += clampf(spd * 0.04, 0.0, 2.5)
			pivot.global_position = pivot.global_position.lerp(tp + Vector3(0, h, 0), clampf(dt * 14.0, 0.0, 1.0))
			pivot.global_rotation = Vector3(pitch, yaw, 0)
			arm.spring_length = dist
			arm.position = Vector3(0.35 if not veh else 0.0, 0, 0)
			cam.rotation = Vector3.ZERO
		"first":
			var head: Vector3 = target.call("head_position") if target.has_method("head_position") else tp + Vector3(0, 1.62, 0)
			pivot.global_position = head
			if veh: pivot.global_rotation = Vector3(pitch, yaw, 0)
			else: pivot.global_rotation = Vector3(pitch, yaw, 0)
			arm.spring_length = 0.0
			arm.position = Vector3.ZERO
			cam.rotation = Vector3.ZERO
		"top":
			# classic top-down: north-up, height grows with speed
			var spd: float = target.linear_velocity.length() if target is RigidBody3D else (target.velocity.length() if target is CharacterBody3D else 0.0)
			_top_h = lerpf(_top_h, 26.0 + spd * 1.1, clampf(dt * 1.5, 0.0, 1.0))
			pivot.global_position = tp + Vector3(0, _top_h, 2.0)
			pivot.global_rotation = Vector3(-1.48, 0, 0)
			arm.spring_length = 0.0
			arm.position = Vector3.ZERO
			cam.rotation = Vector3.ZERO
	if _shake > 0.001:
		cam.h_offset = randf_range(-1, 1) * _shake * 0.05
		cam.v_offset = randf_range(-1, 1) * _shake * 0.05
		_shake = move_toward(_shake, 0.0, dt * 2.0)
	else:
		cam.h_offset = 0.0; cam.v_offset = 0.0
