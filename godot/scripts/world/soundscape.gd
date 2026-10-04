class_name Soundscape
extends Node3D
## Street sound: an ambient traffic bed and crowd murmur that follow how busy the streets around
## the listener are, engine loops on nearby vehicles (pitched with speed), horns — from drivers
## who are blocked and, Chennai style, from everyone else too — and crows in the trees.
## Sounds come from tools/audio/gen.py (procedural placeholders, docs/PLACEHOLDERS.md).

const HORN := {"bike": "horn_bike", "scooter": "horn_scooter", "auto": "horn_auto", "hatch": "horn_car", "bus": "horn_bus", "lorry": "horn_bus", "minitruck": "horn_car", "cycle": "horn_scooter"}
const ENGINE := {"bike": "engine_bike", "scooter": "engine_scooter", "auto": "engine_auto", "hatch": "engine_car", "bus": "engine_bus", "lorry": "engine_bus", "minitruck": "engine_car", "cycle": ""}

static var _streams := {}
var world: World
var amb_traffic: AudioStreamPlayer
var amb_crowd: AudioStreamPlayer
var _horns: Array[AudioStreamPlayer3D] = []
var _next_horn := 0
var _t_random_horn := 0.0
var _t_crow := 4.0
var rng := Rng.new(808)

static func stream(name: String, loop := false) -> AudioStream:
	var key := name + ("_l" if loop else "")
	if _streams.has(key): return _streams[key]
	var s: AudioStream = load("res://audio/%s.wav" % name)
	if s is AudioStreamWAV and loop:
		var w: AudioStreamWAV = (s as AudioStreamWAV).duplicate()
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = int(w.get_length() * w.mix_rate)
		s = w
	_streams[key] = s
	return s

func setup(w: World) -> void:
	world = w
	amb_traffic = AudioStreamPlayer.new()
	amb_traffic.stream = stream("amb_traffic", true)
	amb_traffic.volume_db = -14.0
	add_child(amb_traffic)
	amb_crowd = AudioStreamPlayer.new()
	amb_crowd.stream = stream("amb_crowd", true)
	amb_crowd.volume_db = -20.0
	add_child(amb_crowd)
	amb_traffic.play(); amb_crowd.play()
	for i in 8:
		var p := AudioStreamPlayer3D.new()
		p.unit_size = 9.0
		p.max_distance = 220.0
		p.attenuation_filter_cutoff_hz = 4000.0
		add_child(p)
		_horns.append(p)

## a horn at a world position (pooled players, oldest reused)
func honk(kind: String, at: Vector3, pitch := 1.0) -> void:
	var p := _horns[_next_horn]
	_next_horn = (_next_horn + 1) % _horns.size()
	if kind == "cycle": return
	p.stream = stream(HORN.get(kind, "horn_car"))
	p.global_position = at + Vector3(0, 1.0, 0)
	p.pitch_scale = pitch * rng.range_f(0.94, 1.06)
	p.volume_db = rng.range_f(-4.0, 2.0)
	p.play()

## an engine loop that lives on a pooled vehicle body
static func engine_player(kind: String) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.name = "engine"
	if ENGINE.get(kind, "x") == "": p.volume_db = -80.0; return p   # bicycles are silent (bell later)
	p.stream = stream(ENGINE.get(kind, "engine_car"), true)
	p.unit_size = 3.0 if kind in ["bike", "scooter"] else (4.0 if kind == "auto" else 5.0)
	p.max_distance = 70.0
	p.volume_db = -6.0 if kind != "bus" else 0.0
	p.position = Vector3(0, 0.6, 0.4)
	p.autoplay = false
	return p

func _process(dt: float) -> void:
	if world == null: return
	var tr: Traffic = world.traffic
	var cr: Crowd = world.crowd
	# ambience beds follow how much is going on nearby
	var busy := 0.0
	if tr: busy = clampf(float(tr.stats.get("agents", 0)) / 260.0, 0.0, 1.0)
	amb_traffic.volume_db = lerpf(amb_traffic.volume_db, lerpf(-30.0, -9.0, busy), clampf(dt, 0.0, 1.0))
	var people := 0.0
	if cr: people = clampf(float(cr.stats.get("near", 0)) / 25.0, 0.0, 1.0)
	amb_crowd.volume_db = lerpf(amb_crowd.volume_db, lerpf(-34.0, -14.0, people), clampf(dt, 0.0, 1.0))
	# random honks from the traffic within earshot (blocked drivers honk from Traffic itself)
	_t_random_horn -= dt
	if tr and _t_random_horn <= 0.0 and not tr.agents.is_empty():
		_t_random_horn = rng.range_f(0.4, 2.2) / maxf(0.3, busy)
		var a: Dictionary = tr.agents[int(rng.next() * tr.agents.size()) % tr.agents.size()]
		if float(a.d) < 140.0:
			honk(a.kind, (a.xf as Transform3D).origin)
	# crows from the trees overhead
	_t_crow -= dt
	if _t_crow <= 0.0:
		_t_crow = rng.range_f(3.0, 14.0)
		var p := _horns[_next_horn]
		_next_horn = (_next_horn + 1) % _horns.size()
		p.stream = stream("crow")
		var f := world.streamer.focus
		p.global_position = Vector3(f.x + rng.range_f(-30, 30), rng.range_f(6, 14), f.y + rng.range_f(-30, 30))
		p.pitch_scale = rng.range_f(0.85, 1.15)
		p.volume_db = rng.range_f(-10.0, -3.0)
		p.play()
