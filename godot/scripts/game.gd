extends Node3D
## Game root. Builds the world for the selected city, spawns the player and cameras, and either
## runs interactively or, with `-- --shot=<set>`, runs the screenshot/verification harness.

var world: World
var player: Node3D
var cam_rig: CameraRig
var hud: Hud
var harness: Harness

func _ready() -> void:
	world = World.new()
	world.name = "World"
	add_child(world)
	world.setup(Settings.get_v("city"))
	hud = Hud.new()
	hud.name = "Hud"
	add_child(hud)
	hud.world = world
	if Settings.has_arg("shot"):
		harness = Harness.new()
		harness.name = "Harness"
		add_child(harness)
		harness.start(self)
		return
	_spawn_player()

func _spawn_player() -> void:
	var sp: Dictionary = world.pack.pack.spawn
	var pos := Vector3(float(sp.x), 0.5, float(sp.z))
	if Settings.has_arg("spawn"):
		var v := Settings.arg_vec("spawn")
		pos = Vector3(v[0], 0.5, v[1])
	_spawn_player_at(pos)
	player.rotation.y = float(sp.get("heading", 0.0))
	VehicleSpawner.spawn_demo(self, world, pos)

func _spawn_player_at(pos: Vector3) -> void:
	if player: return
	player = load("res://scripts/player/player.gd").new()
	player.name = "Player"
	add_child(player)
	player.global_position = pos
	cam_rig = CameraRig.new()
	cam_rig.name = "CameraRig"
	add_child(cam_rig)
	cam_rig.follow(player)
	player.set("cam_rig", cam_rig)
	player.set("world", world)
	hud.player = player
	hud.cam_rig = cam_rig

func _process(_dt: float) -> void:
	if harness: return
	if player: world.set_focus(player.global_position)
	if Input.is_action_just_pressed("time_fwd"): world.clock.hour = fmod(world.clock.hour + 1.0, 24.0)
	if Input.is_action_just_pressed("time_back"): world.clock.hour = fmod(world.clock.hour + 23.0, 24.0)
	if Input.is_action_just_pressed("debug_toggle"): hud.visible = not hud.visible
	if Input.is_action_just_pressed("pause"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED
