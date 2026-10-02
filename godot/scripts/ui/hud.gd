class_name Hud
extends CanvasLayer
## Debug stats overlay (FPS, draw calls, primitives, memory, chunks, NPC/vehicle counts) plus
## the clock and the current street name. Toggle with F3.

var world: World
var player: Node3D
var cam_rig: Node
var label: Label
var street_label: Label
var npc_count := 0
var vehicle_count := 0
var _acc := 0.0

func _ready() -> void:
	layer = 10
	label = Label.new()
	label.position = Vector2(10, 8)
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color(1, 1, 1))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("outline_size", 4)
	add_child(label)
	street_label = Label.new()
	street_label.anchor_left = 1.0; street_label.anchor_right = 1.0
	street_label.offset_left = -420; street_label.offset_right = -16; street_label.offset_top = 12
	street_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var f := FontVariation.new()
	f.base_font = load("res://fonts/BalooThambi2_wght.ttf")
	f.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 700}
	street_label.add_theme_font_override("font", f)
	street_label.add_theme_font_size_override("font_size", 22)
	street_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	street_label.add_theme_constant_override("outline_size", 6)
	add_child(street_label)
	visible = Settings.get_v("debug")

func _process(dt: float) -> void:
	_acc += dt
	if _acc < 0.25: return
	_acc = 0.0
	if world == null: return
	var s: Dictionary = world.streamer.stats
	var t := "GTIndian  %d fps  %.1f ms\n" % [Engine.get_frames_per_second(), 1000.0 / maxf(1.0, Engine.get_frames_per_second())]
	t += "draws %d  prims %.2fM  objs %d\n" % [RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME), RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME) / 1e6, RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)]
	t += "vram %d MB  mem %d MB\n" % [RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576, OS.get_static_memory_usage() / 1048576]
	t += "chunks %d near %d far (%d pending, gen %.0f ms, upload max %.1f ms)\n" % [s.near, s.far, s.pending, s.last_ms, s.max_upload_ms]
	t += "time %s  NPCs %d (%d near)  vehicles %d (traffic %d)\n" % [world.clock.clock_text(), world.crowd.stats.agents if world.crowd else 0, world.crowd.stats.near if world.crowd else 0, vehicle_count, world.traffic.stats.agents if world.traffic else 0]
	if player:
		var p := player.global_position
		t += "pos %.0f, %.0f   cam %s" % [p.x, p.z, cam_rig.get("mode") if cam_rig else ""]
		var r := world.pack.nearest_road(p.x, p.z, 25.0, 0)
		var road: Dictionary = world.pack.region.roads[r.ri] if not r.is_empty() else {}
		street_label.text = road.get("name", "") if road.get("nameTa", "") == "" else "%s\n%s" % [road.nameTa, road.name]
	label.text = t
