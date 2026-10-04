extends SceneTree
## headless traffic sim check: `godot --headless --path godot -s res://scripts/tools/traffic_test.gd`
func _initialize() -> void:
	var pack := CityPack.new("chennai")
	pack.load_region("mylapore_marina")
	var t := Traffic.new()
	root.add_child(t)
	t.setup(pack, null)
	t.focus = Vector3(-96, 0, -301)
	t.populate(10.0)
	print("populated ", t.agents.size())
	var kinds := {}
	for a in t.agents: kinds[a.kind] = kinds.get(a.kind, 0) + 1
	print(kinds)
	for i in 50:
		t.update(0.2, 10.0)
		if i % 10 == 0: print("t=", i * 0.2, " agents ", t.agents.size(), " near ", t.stats.near)
	var on_k := 0
	for a in t.agents:
		if a.d < 60.0: on_k += 1
	print("within 60 m: ", on_k)
	quit()
