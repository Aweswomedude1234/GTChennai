class_name SkyClock
extends Node3D
## Day/night cycle tuned to Chennai light (STYLE_BIBLE §1): harsh white noon haze, golden
## 17:15–18:10 evenings, a short dusk, and an orange-brown light-polluted night sky.
## Drives the sun, sky shader, fog, exposure and the global shader uniforms (night, hour, wet, power).

var hour := 17.6
var day_speed := 1.0 / 60.0   # game hours per real second (1 game day = 24 real minutes)
var paused := false
var wet := 0.0
var power := 1.0
var weather_dim := 1.0
var weather_fog := 1.0
var night_factor := 0.0
var sun_dir := Vector3.UP
var sun: DirectionalLight3D
var env: Environment
var sky_mat: ShaderMaterial
var focus := Vector3.ZERO
var _lights_on := true

# h, sun colour, sun intensity, sky zenith, horizon, ambient energy, fog colour, fog density, exposure
const KEYS := [
	[0.0, "#8ea2c8", 0.08, "#0b0e1a", "#2c1b10", 0.35, "#1c1a1e", 0.0013, 1.6],
	[4.8, "#8ea2c8", 0.07, "#0b0e1a", "#2c1b10", 0.35, "#1e1c20", 0.0014, 1.6],
	[5.7, "#d08a68", 0.25, "#3c4664", "#a07a6a", 0.5, "#76707a", 0.0018, 1.35],
	[6.4, "#ffa868", 1.4, "#8ca2c0", "#e6bc98", 0.75, "#d6b49c", 0.0017, 1.05],
	[8.0, "#ffe6c4", 2.6, "#a2bcd8", "#e2e2dc", 0.9, "#cfd2d2", 0.0011, 0.95],
	[12.0, "#fff8ee", 3.4, "#b4c9de", "#e4e6e4", 1.0, "#d9dad6", 0.0009, 0.85],
	[15.5, "#ffefd6", 3.0, "#acc2da", "#e2dfd6", 0.95, "#d8d4cc", 0.0010, 0.9],
	[17.3, "#ffc27a", 2.2, "#9cb0c8", "#ecc79a", 0.85, "#e2c09a", 0.0011, 0.95],
	[18.1, "#ff8a48", 0.9, "#6a6e90", "#e09868", 0.7, "#b48a78", 0.0014, 1.1],
	[18.8, "#b06850", 0.2, "#2e3250", "#8a5a48", 0.5, "#5a4c52", 0.0015, 1.35],
	[19.8, "#8ea2c8", 0.08, "#0b0e1a", "#2c1b10", 0.35, "#2c2a30", 0.0014, 1.6],
	[24.0, "#8ea2c8", 0.08, "#0b0e1a", "#2c1b10", 0.35, "#1c1a1e", 0.0013, 1.6],
]

func _ready() -> void:
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = Settings.q("shadows")
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 220.0
	sun.directional_shadow_split_1 = 0.06
	sun.directional_shadow_split_2 = 0.18
	sun.directional_shadow_split_3 = 0.45
	sun.directional_shadow_blend_splits = true
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	sun.shadow_blur = 1.2
	sun.light_angular_distance = 0.6
	add_child(sun)
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = Sky.new()
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = load("res://shaders/sky.gdshader")
	env.sky.sky_material = sky_mat
	env.sky.radiance_size = Sky.RADIANCE_SIZE_256
	env.sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_white = 6.0
	env.ssao_enabled = Settings.q("ssao")
	env.ssao_radius = 1.4
	env.ssao_intensity = 2.2
	env.ssao_power = 1.6
	env.ssao_detail = 0.6
	env.ssil_enabled = Settings.q("ssil")
	env.ssil_radius = 4.0
	env.ssil_intensity = 0.8
	env.glow_enabled = Settings.q("glow")
	env.glow_intensity = 0.55
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.3
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_aerial_perspective = 0.4
	env.fog_sky_affect = 0.25
	env.fog_sun_scatter = 0.25
	env.sdfgi_enabled = Settings.q("sdfgi")
	env.sdfgi_use_occlusion = true
	env.sdfgi_cascades = 4
	env.sdfgi_min_cell_size = 0.25
	env.volumetric_fog_enabled = Settings.q("volumetric")
	env.volumetric_fog_density = 0.004
	env.volumetric_fog_length = 120.0
	env.volumetric_fog_anisotropy = 0.6
	env.volumetric_fog_ambient_inject = 0.3
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.14
	env.adjustment_contrast = 1.04
	we.environment = env
	add_child(we)
	if Settings.has_arg("hour"): hour = Settings.arg_f("hour")
	if Settings.has_arg("freeze"): paused = true
	if Settings.has_arg("wet"): wet = Settings.arg_f("wet")
	_apply()

func _process(dt: float) -> void:
	if not paused: hour = fmod(hour + dt * day_speed, 24.0)
	_apply()

static func _lerp_key(h: float) -> Array:
	var i := 0
	while i < KEYS.size() - 2 and KEYS[i + 1][0] <= h: i += 1
	var a: Array = KEYS[i]; var b: Array = KEYS[i + 1]
	var t: float = (h - a[0]) / maxf(b[0] - a[0], 0.0001)
	var out := []
	for k in a.size():
		if a[k] is String: out.append(Color(a[k]).lerp(Color(b[k]), t))
		else: out.append(lerpf(a[k], b[k], t))
	return out

func _apply() -> void:
	var h := hour
	# Sun path: rises ~06:05 in the east (+x), sets ~18:15 in the west. Chennai is at 13°N so the
	# sun passes close to overhead with a slight southern (+z) tilt.
	var th := ((h - 6.08) / 12.15) * PI
	sun_dir = Vector3(cos(th), sin(th), 0.28 * maxf(0.2, sin(th))).normalized()
	var k := _lerp_key(h)
	var below := sun_dir.y < 0.02
	var light_dir := sun_dir
	if below: light_dir = Vector3(-sun_dir.x, absf(sun_dir.y) + 0.45, -sun_dir.z).normalized()  # moon
	sun.light_color = k[1]
	sun.light_energy = k[2] * weather_dim * 0.72
	sun.look_at_from_position(focus + light_dir * 100.0, focus, Vector3.UP if absf(light_dir.y) < 0.99 else Vector3.FORWARD)
	night_factor = smoothstep(-0.08, 0.12, -sun_dir.y)
	sky_mat.set_shader_parameter("zenith", k[3])
	sky_mat.set_shader_parameter("horizon", k[4])
	sky_mat.set_shader_parameter("sun_col", k[1])
	sky_mat.set_shader_parameter("night_f", night_factor)
	sky_mat.set_shader_parameter("ground_col", Color("#5a5048"))
	env.ambient_light_energy = k[5] * (0.7 + 0.3 * weather_dim)
	env.fog_light_color = (k[6] as Color) * (0.75 + 0.25 * weather_dim)
	env.fog_density = k[7] * weather_fog
	env.volumetric_fog_albedo = k[6]
	env.tonemap_exposure = k[8]
	var lights_on := street_lights_on() and power > 0.5
	if lights_on != _lights_on or Engine.get_process_frames() % 30 == 0:
		_lights_on = lights_on
		for n in get_tree().get_nodes_in_group("street_lights"): n.visible = lights_on
	RenderingServer.global_shader_parameter_set("night", night_factor)
	RenderingServer.global_shader_parameter_set("hour", h)
	RenderingServer.global_shader_parameter_set("wet", wet)
	RenderingServer.global_shader_parameter_set("power", power)

func street_lights_on() -> bool:
	return hour > 18.3 or hour < 6.0

func clock_text() -> String:
	var hh := int(hour); var mm := int((hour - hh) * 60.0)
	return "%02d:%02d" % [hh, mm]
