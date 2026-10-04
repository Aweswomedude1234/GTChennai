extends SceneTree
## headless memory check of the world + crowd + traffic: `godot --headless -s res://scripts/tools/mem_test.gd`
var w: World
var frames := 0
func rss() -> String:
	var f := FileAccess.open("/proc/self/status", FileAccess.READ)
	var t := f.get_as_text()
	for l in t.split("\n"):
		if l.begins_with("VmRSS"): return l
	return ""
func _initialize() -> void:
	print("start ", rss())
	w = World.new()
	root.add_child(w)
	w.setup("chennai")
	print("world ", rss(), " static ", OS.get_static_memory_usage() / 1048576)
	w.set_focus(Vector3(-96, 0, -301))
func _process(_dt: float) -> bool:
	frames += 1
	w.set_focus(Vector3(-96, 0, -301))
	if frames % 50 == 0:
		print("f", frames, " ", rss(), " static ", OS.get_static_memory_usage() / 1048576, " chunks ", w.streamer.stats.near, "/", w.streamer.stats.far, " crowd ", w.crowd.stats if w.crowd else {}, " traffic ", w.traffic.stats if w.traffic else {})
	if frames == 150 and w.traffic:
		w.traffic.focus = Vector3(-96, 0, -301)
		w.traffic.populate(10.0)
		print("populated ", rss())
	return frames > 400
