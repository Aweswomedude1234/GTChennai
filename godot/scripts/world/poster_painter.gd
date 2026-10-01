class_name PosterPainter
extends RefCounted
## Paints the global poster atlas once at startup: political posters for the fictional parties
## (TMEK: maroon/teal + lighthouse; ATM: sky-blue/white/yellow + palmyra; STYLE_BIBLE §10),
## film posters (fictional titles), kanneer-anjali memorial posters, birthday/wedding flex,
## tuition and gold-loan ads, plus wide political wall-writing panels.
## Portrait cells (192×256) fill rows 0–3; wide wall panels (384×96) fill rows below.

const PW := 192
const PH := 256
const PCOLS := 8
const PROWS := 4
const WW := 384
const WH := 96
const WCOLS := 4
const WROWS := 6
const W := PW * PCOLS                       # 1536
const H := PH * PROWS + WH * WROWS          # 1600
const N_POSTERS := PCOLS * PROWS
const N_WALLS := WCOLS * WROWS

const FILMS := [["வேட்டைக்காரன் 2", "VETTAIKAARAN 2"], ["மெட்ராஸ் ராஜா", "MADRAS RAJA"], ["கருப்பு நிலா", "KARUPPU NILAA"], ["சிங்கார சென்னை", "SINGAARA CHENNAI"],
	["தீப்பொறி", "THEEPPORI"], ["அம்மா சத்தியம்", "AMMA SATHIYAM"], ["கடல் காற்று", "KADAL KAATRU"], ["காசிமேடு", "KASIMEDU"]]
const NAMES := ["முருகேசன்", "செல்வம்", "ராஜேஸ்வரி", "பாண்டியன்", "கலைவாணி", "சுப்பிரமணி", "தங்கராஜ்", "மீனாட்சி"]

static func paint(sp: SignPainter) -> ImageTexture:
	while sp.busy: await sp.get_tree().process_frame
	sp.busy = true
	var job := _Job.new()
	job.sp = sp
	sp.vp.size = Vector2i(W, H)
	var c := _Canvas.new()
	c.job = job
	sp.vp.add_child(c)
	sp.canvas.visible = false
	c.queue_redraw()
	sp.vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	var img := sp.vp.get_texture().get_image()
	c.queue_free()
	sp.canvas.visible = true
	sp.busy = false
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

class _Job:
	var sp: SignPainter

class _Canvas extends Node2D:
	var job: _Job
	func _draw() -> void:
		for i in N_POSTERS:
			draw_set_transform(Vector2((i % PCOLS) * PW, (i / PCOLS) * PH))
			PosterPainter._poster(self, job.sp, i)
		for i in N_WALLS:
			draw_set_transform(Vector2((i % WCOLS) * WW, PH * PROWS + (i / WCOLS) * WH))
			PosterPainter._wall(self, job.sp, i)
		draw_set_transform(Vector2.ZERO)

static func _grad(ci: CanvasItem, r: Rect2, a: Color, b: Color, vertical := true) -> void:
	var p := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	ci.draw_polygon(p, PackedColorArray([a, b, b, a]) if not vertical else PackedColorArray([a, a, b, b]))

## stylised portrait (head, hair, shoulders, white shirt / saree) — posters always carry a face
static func _portrait(ci: CanvasItem, c: Vector2, s: float, skin: Color, female := false, garland := false, shirt := Color(0.96, 0.96, 0.94)) -> void:
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 1.1, s * 2.4), c + Vector2(-s * 0.9, s * 1.2), c + Vector2(-s * 0.3, s * 0.95), c + Vector2(s * 0.3, s * 0.95), c + Vector2(s * 0.9, s * 1.2), c + Vector2(s * 1.1, s * 2.4)]), shirt)
	ci.draw_rect(Rect2(c + Vector2(-s * 0.18, s * 0.6), Vector2(s * 0.36, s * 0.45)), skin.darkened(0.1))
	ci.draw_circle(c + Vector2(0, s * 0.15), s * 0.62, skin)
	var hair := Color(0.06, 0.05, 0.04)
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.62, s * 0.05), c + Vector2(-s * 0.5, -s * 0.42), c + Vector2(0, -s * 0.58), c + Vector2(s * 0.5, -s * 0.42), c + Vector2(s * 0.62, s * 0.05), c + Vector2(s * 0.45, -s * 0.2), c + Vector2(-s * 0.45, -s * 0.2)]), hair)
	if female:
		ci.draw_circle(c + Vector2(0, s * 0.05), s * 0.07, Color(0.75, 0.05, 0.08))  # pottu
		ci.draw_rect(Rect2(c + Vector2(-s * 0.7, -s * 0.1), Vector2(s * 0.12, s * 1.2)), hair)
		ci.draw_rect(Rect2(c + Vector2(s * 0.58, -s * 0.1), Vector2(s * 0.12, s * 1.2)), hair)
	else:
		ci.draw_rect(Rect2(c + Vector2(-s * 0.25, s * 0.42), Vector2(s * 0.5, s * 0.09)), hair)  # moustache
		ci.draw_rect(Rect2(c + Vector2(-s * 0.08, -s * 0.12), Vector2(s * 0.16, s * 0.05)), Color(1, 1, 1, 0.9))  # vibhuti/namam stroke
	for e in [-1.0, 1.0]:
		ci.draw_circle(c + Vector2(e * s * 0.22, s * 0.12), s * 0.06, Color(0.08, 0.06, 0.05))
	if garland:
		for k in 14:
			var a := PI * 0.05 + PI * 0.9 * k / 13.0
			ci.draw_circle(c + Vector2(cos(a) * s * 0.85, s * 1.15 + sin(a) * s * 0.6), s * 0.12, Color(0.98, 0.95, 0.85) if k % 3 else Color(0.95, 0.45, 0.1))

static func _lighthouse(ci: CanvasItem, c: Vector2, s: float, col: Color) -> void:
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.3, s), c + Vector2(-s * 0.15, -s * 0.6), c + Vector2(s * 0.15, -s * 0.6), c + Vector2(s * 0.3, s)]), col)
	ci.draw_rect(Rect2(c + Vector2(-s * 0.2, -s * 0.85), Vector2(s * 0.4, s * 0.25)), col)
	for a in [-0.5, 0.5]:
		ci.draw_line(c + Vector2(0, -s * 0.72), c + Vector2(a * s * 2.0, -s * 0.95), col, 2.0)

static func _palmyra(ci: CanvasItem, c: Vector2, s: float, col: Color) -> void:
	ci.draw_line(c + Vector2(0, s), c + Vector2(0, -s * 0.4), col, s * 0.18)
	for k in 9:
		var a := -PI * 0.95 + PI * 0.9 * k / 8.0
		ci.draw_line(c + Vector2(0, -s * 0.4), c + Vector2(cos(a), sin(a)) * s * 0.75 + Vector2(0, -s * 0.4), col, s * 0.1)

static func _poster(ci: CanvasItem, sp: SignPainter, i: int) -> void:
	var r := Rng.new(9001 + i * 131)
	var kind := i % 8
	var f: Dictionary = sp.fonts
	var skin := Color(Appearance.SKIN[r.pick_w(Appearance.SKIN_W)])
	match kind:
		0, 4:  # TMEK
			_grad(ci, Rect2(0, 0, PW, PH), Color("#7a1f3d"), Color("#1f7a74"))
			_portrait(ci, Vector2(PW * 0.5, PH * 0.36), 34, skin, false, kind == 4)
			_lighthouse(ci, Vector2(28, 40), 20, Color(1, 1, 1))
			sp._text_c(ci, f.baloo, "எழுந்து வா!", PW * 0.5, PH * 0.83, sp._fit(f.baloo, "எழுந்து வா!", PW - 16, 30), Color("#ffe082"), true)
			var org := "தமிழ் மக்கள் எழுச்சி கழகம்"
			sp._text_c(ci, f.baloo6, org, PW * 0.5, PH * 0.93, sp._fit(f.baloo6, org, PW - 10, 14), Color(1, 1, 1))
			sp._text_c(ci, f.anton, "AADHAVAN", PW * 0.5, PH * 0.73, 20, Color(1, 1, 1), true)
		1, 5:  # ATM
			for k in 3:
				ci.draw_rect(Rect2(PW * k / 3.0, 0, PW / 3.0 + 1, PH), [Color("#4fa3d9"), Color("#ffffff"), Color("#f2c230")][k])
			ci.draw_rect(Rect2(0, PH * 0.66, PW, PH * 0.34), Color(0.05, 0.12, 0.3, 0.85))
			_portrait(ci, Vector2(PW * 0.5, PH * 0.32), 32, skin, false, kind == 5, Color(0.98, 0.98, 0.98))
			_palmyra(ci, Vector2(PW - 30, 42), 22, Color(0.05, 0.05, 0.05))
			sp._text_c(ci, f.mukta, "எல்லோருக்கும் எல்லாம்", PW * 0.5, PH * 0.8, sp._fit(f.mukta, "எல்லோருக்கும் எல்லாம்", PW - 12, 24), Color("#f2c230"), true)
			sp._text_c(ci, f.oswald, "NAGARAJ  •  A.T.M.", PW * 0.5, PH * 0.93, 15, Color(1, 1, 1))
		2, 6:  # film poster
			var film: Array = FILMS[(i / 8 + kind) % FILMS.size()]
			var c1 := Color(r.pick(["#1a0a0a", "#0a1020", "#201008", "#0c1a10"]))
			_grad(ci, Rect2(0, 0, PW, PH), c1.lightened(0.25), c1)
			ci.draw_circle(Vector2(PW * 0.5, PH * 0.38), 70, Color(r.pick(["#ff6a00", "#c62828", "#ffb300", "#2979ff"]), 0.35))
			_portrait(ci, Vector2(PW * 0.5, PH * 0.34), 40, skin, false, false, Color(0.1, 0.1, 0.12))
			var t_px := sp._fit(f.catamaran, film[0], PW - 14, 34)
			sp._text_c(ci, f.catamaran, film[0], PW * 0.5, PH * 0.82, t_px, Color("#ffd54f"), true)
			sp._text_c(ci, f.anton, film[1], PW * 0.5, PH * 0.9, sp._fit(f.anton, film[1], PW - 14, 16), Color(1, 1, 1))
			sp._text_c(ci, f.baloo6, "இன்று முதல்" if r.next() < 0.5 else "விரைவில்", PW * 0.5, PH * 0.97, 13, Color("#ff8a65"))
		3:  # kanneer anjali (memorial)
			ci.draw_rect(Rect2(0, 0, PW, PH), Color(0.97, 0.97, 0.95))
			ci.draw_rect(Rect2(6, 6, PW - 12, PH - 12), Color(0.1, 0.1, 0.1), false, 4.0)
			sp._text_c(ci, f.baloo, "கண்ணீர் அஞ்சலி", PW * 0.5, 36, sp._fit(f.baloo, "கண்ணீர் அஞ்சலி", PW - 20, 26), Color(0.05, 0.05, 0.05))
			_portrait(ci, Vector2(PW * 0.5, PH * 0.45), 30, skin, r.next() < 0.4, true, Color(0.9, 0.9, 0.88))
			var nm: String = r.pick(NAMES)
			sp._text_c(ci, f.mukta, nm, PW * 0.5, PH * 0.84, 22, Color(0.05, 0.05, 0.05))
			sp._text_c(ci, f.sans, "தோற்றம் 1952 • மறைவு 2026", PW * 0.5, PH * 0.93, 11, Color(0.2, 0.2, 0.2))
		7:  # birthday / ad flex
			if r.next() < 0.5:
				_grad(ci, Rect2(0, 0, PW, PH), Color(r.pick(["#e91e63", "#ff9800", "#8e24aa", "#00acc1"])), Color(r.pick(["#311b92", "#bf360c", "#004d40"])))
				_portrait(ci, Vector2(PW * 0.5, PH * 0.38), 32, skin)
				var tx := "இனிய பிறந்தநாள் வாழ்த்துக்கள்"
				sp._text_c(ci, f.baloo, tx, PW * 0.5, PH * 0.8, sp._fit(f.baloo, tx, PW - 10, 20), Color("#fff59d"), true)
				sp._text_c(ci, f.mukta, "அண்ணன் " + r.pick(NAMES), PW * 0.5, PH * 0.92, 18, Color(1, 1, 1))
			else:
				ci.draw_rect(Rect2(0, 0, PW, PH), Color("#0d47a1"))
				ci.draw_rect(Rect2(0, PH * 0.55, PW, PH * 0.45), Color("#ffd600"))
				var t1: String = r.pick(["தங்கம் நகைக்கடன்", "வெற்றி டியூஷன் சென்டர்", "கேசவர்த்தினி ஹேர் ஆயில்", "அன்னை ரியல் எஸ்டேட்"])
				sp._text_c(ci, f.baloo, t1, PW * 0.5, PH * 0.3, sp._fit(f.baloo, t1, PW - 12, 28), Color(1, 1, 1), true)
				var t2: String = r.pick(["THANGAM GOLD LOAN • 0.9% p.m.", "NEET / JEE CRASH COURSE", "KESAVARDHINI HAIR OIL", "PLOTS @ ECR • DTCP APPROVED"])
				sp._text_c(ci, f.oswald, t2, PW * 0.5, PH * 0.72, sp._fit(f.oswald, t2, PW - 12, 18), Color(0.05, 0.1, 0.3))
				sp._text_c(ci, f.sans, SignPainter._phone(r), PW * 0.5, PH * 0.9, 13, Color(0.05, 0.1, 0.3))
	# weathering: sun fading, torn corners, stuck-over remnants
	for k in 10:
		ci.draw_rect(Rect2(r.next() * PW, r.next() * PH, 6 + r.next() * 50, 4 + r.next() * 30), Color(1, 1, 0.95, r.next() * 0.12))
	if r.next() < 0.5:
		ci.draw_colored_polygon(PackedVector2Array([Vector2(PW, 0), Vector2(PW - 18 - r.next() * 30, 0), Vector2(PW, 20 + r.next() * 30)]), Color(0.55, 0.52, 0.48))

static func _wall(ci: CanvasItem, sp: SignPainter, i: int) -> void:
	var r := Rng.new(7001 + i * 97)
	var f: Dictionary = sp.fonts
	ci.draw_rect(Rect2(0, 0, WW, WH), Color(0.95, 0.94, 0.9))
	var party := i % 3
	if party == 0:
		ci.draw_rect(Rect2(0, 0, WW, 12), Color("#7a1f3d")); ci.draw_rect(Rect2(0, WH - 12, WW, 12), Color("#1f7a74"))
		_lighthouse(ci, Vector2(36, WH * 0.55), 26, Color("#7a1f3d"))
		var t: String = r.pick(["வாக்களிப்பீர் கலங்கரை விளக்கம் சின்னத்தில்", "எழுந்து வா! தமிழ் மக்கள் எழுச்சி கழகம்", "ஆதவன் ஆட்சி அமைய வாக்களிப்பீர்"])
		sp._text_c(ci, f.baloo, t, WW * 0.55, WH * 0.62, sp._fit(f.baloo, t, WW - 90, 30), Color("#7a1f3d"))
	elif party == 1:
		for k in 3: ci.draw_rect(Rect2(WW - 60 + k * 20, 0, 20, WH), [Color("#4fa3d9"), Color(1, 1, 1), Color("#f2c230")][k])
		_palmyra(ci, Vector2(WW - 30, WH * 0.55), 26, Color(0.05, 0.05, 0.05))
		var t: String = r.pick(["வாக்களிப்பீர் பனைமரம் சின்னத்தில்", "எல்லோருக்கும் எல்லாம் — அ.த.மு.", "நாகராஜ் வெற்றி நிச்சயம்"])
		sp._text_c(ci, f.mukta, t, WW * 0.45, WH * 0.62, sp._fit(f.mukta, t, WW - 90, 30), Color("#0d47a1"))
	else:
		# civic / commercial wall painting
		var t: String = r.pick(["இங்கு சுவரொட்டி ஒட்டாதீர்", "சுத்தமான சென்னை • CLEAN CHENNAI", "இங்கு சிறுநீர் கழிக்காதீர்", "அன்னை அரிசி • ANNAI RICE"])
		sp._text_c(ci, f.hind, t, WW * 0.5, WH * 0.62, sp._fit(f.hind, t, WW - 20, 28), Color(r.pick(["#b71c1c", "#1b5e20", "#0d47a1"])))
	for k in 14:
		ci.draw_rect(Rect2(r.next() * WW, r.next() * WH, 10 + r.next() * 70, 3 + r.next() * 20), Color(0.45, 0.4, 0.33, r.next() * 0.15))
