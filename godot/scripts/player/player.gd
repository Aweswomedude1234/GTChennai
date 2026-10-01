extends CharacterBody3D
## The player on foot: walk / jog / sprint / jump, step-up over kerbs and plinths, entering and
## leaving vehicles. Movement is camera-relative (top-down mode is screen-relative, north up).

var cam_rig: CameraRig
var world: World
var body: HumanActor
var vehicle: Node = null
var walk_speed := 1.5
var jog_speed := 3.4
var sprint_speed := 6.2
var jump_v := 4.4
var gravity := 14.0
var stamina := 1.0
var _shape: CollisionShape3D

func _ready() -> void:
	add_to_group("player")
	floor_snap_length = 0.45
	floor_max_angle = deg_to_rad(50.0)
	safe_margin = 0.02
	_shape = CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.28
	cap.height = 1.75
	_shape.shape = cap
	_shape.position.y = 0.875
	add_child(_shape)
	body = HumanActor.new()
	add_child(body)
	# Selva: 29, back from Dubai — shirt and trousers, a moustache, mid-brown skin
	var spec: Dictionary = HumanActor.pick_spec(Rng.new(29), "m", false, "shirt_pants")
	var a := HumanActor.appearance_for(spec, Rng.new(29))
	a.skin = Color("#8c5e3e"); a.top = Color("#7fa2c8"); a.lower = Color("#2b2b2b"); a.top_pattern = 0
	body.build(spec, a, 29)


func get_exclusions() -> Array:
	return [get_rid()]

func head_position() -> Vector3:
	return global_position + Vector3(0, 1.62, 0) - global_basis.z * 0.12

func _physics_process(dt: float) -> void:
	if vehicle: return
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var b := cam_rig.move_basis() if cam_rig else Basis()
	var dir := (b * Vector3(input.x, 0, input.y))
	dir.y = 0
	var mag := minf(1.0, dir.length())
	dir = dir.normalized()
	var spd := jog_speed
	if Input.is_action_pressed("walk"): spd = walk_speed
	if Input.is_action_pressed("sprint") and stamina > 0.05:
		spd = sprint_speed
		stamina = maxf(0.0, stamina - dt * 0.12)
	else:
		stamina = minf(1.0, stamina + dt * 0.2)
	var target := dir * spd * mag
	var accel := 12.0 if is_on_floor() else 2.5
	velocity.x = move_toward(velocity.x, target.x, accel * dt * maxf(spd, 2.0))
	velocity.z = move_toward(velocity.z, target.z, accel * dt * maxf(spd, 2.0))
	if is_on_floor():
		if Input.is_action_just_pressed("jump"): velocity.y = jump_v
	else:
		velocity.y -= gravity * dt
	# face the direction of travel (first-person: face the camera)
	if cam_rig and cam_rig.mode == "first":
		rotation.y = cam_rig.yaw
	elif mag > 0.1:
		rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), clampf(dt * 10.0, 0.0, 1.0))
	_step_up(dt)
	move_and_slide()
	body.animate(dt, Vector2(velocity.x, velocity.z).length())
	if global_position.y < -30.0: global_position = Vector3(global_position.x, 2.0, global_position.z)
	if Input.is_action_just_pressed("interact"): _try_enter()

## climb kerbs, shop plinths and steps up to 0.5 m without jumping
func _step_up(dt: float) -> void:
	if not is_on_floor(): return
	var h := Vector3(velocity.x, 0, velocity.z) * dt
	if h.length() < 0.001: return
	var probe := h.normalized() * maxf(h.length(), 0.08)
	if not test_move(global_transform, probe): return
	var up := Vector3(0, 0.5, 0)
	if test_move(global_transform, up): return
	var raised := global_transform.translated(up)
	if test_move(raised, probe): return
	global_position += up
	apply_floor_snap()

func _try_enter() -> void:
	var best: Node3D = null
	var bd := 3.2
	for v in get_tree().get_nodes_in_group("vehicles"):
		var d: float = (v as Node3D).global_position.distance_to(global_position)
		if d < bd and v.driver == null:
			bd = d; best = v
	if best == null: return
	_enter(best)

func _enter(best: Node3D) -> void:
	vehicle = best
	best.enter(self)
	visible = false
	_shape.disabled = true
	cam_rig.follow(best)

func exit_vehicle() -> void:
	if vehicle == null: return
	var v: Node3D = vehicle
	var side: Vector3 = v.global_basis.x * (-1.4 if v.get("exit_left") else 1.4)
	global_position = v.global_position + side + Vector3(0, 0.3, 0)
	rotation.y = v.global_rotation.y
	velocity = Vector3.ZERO
	vehicle = null
	visible = true
	_shape.disabled = false
	cam_rig.follow(self)
