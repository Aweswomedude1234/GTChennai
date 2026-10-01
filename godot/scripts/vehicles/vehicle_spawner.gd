class_name VehicleSpawner
extends RefCounted
## Places a few drivable vehicles near the player for Phase 1 (an auto, a bike, a hatchback),
## parked at the kerb of the nearest road. Phase 3 replaces this with the traffic system.

static func make(kind: String, seed: int) -> Vehicle:
	var d: Dictionary
	match kind:
		"auto": d = VehicleDefs.auto_rickshaw(seed)
		"bike": d = VehicleDefs.bike(seed)
		_: d = VehicleDefs.car(seed)
	var v := Vehicle.new()
	v.name = kind + "_%d" % seed
	v.setup(d)
	return v

static func spawn_demo(game: Node, world: World, pos: Vector3) -> Array:
	var out := []
	var rr := world.pack.nearest_road(pos.x, pos.z, 120.0, 1)
	var base := Vector2(pos.x, pos.z)
	var dir := Vector2(0, -1)
	var w := 6.0
	if not rr.is_empty():
		base = rr.p; dir = rr.dir; w = rr.w
	var side := Vector2(-dir.y, dir.x)
	var kinds := ["auto", "bike", "car", "auto"]
	for i in kinds.size():
		var p := base + dir * (6.0 + i * 6.5) + side * (w * 0.5 - 1.1)
		var v := make(kinds[i], 1000 + i * 77)
		game.add_child(v)
		v.global_position = Vector3(p.x, 0.6, p.y)
		v.rotation.y = atan2(-dir.x, -dir.y)
		out.append(v)
	return out
