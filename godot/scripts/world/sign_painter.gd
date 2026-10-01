class_name SignPainter
extends Node
## Paints unique Tamil + English shop signboards into a per-chunk atlas (STYLE_BIBLE §3):
## Tamil first and largest; 60% printed flex (saturated gradients, emblem, address, phone),
## 40% hand-painted enamel (border, display lettering, rust and weathering).
## Godot shapes Tamil with HarfBuzz, so conjuncts and vowel signs render correctly.
## Renders on the main thread through a SubViewport; one atlas per chunk.

const CW := BuildingGen.SIGN_CW
const CH := BuildingGen.SIGN_CH
const COLS := BuildingGen.SIGN_COLS

var names: Dictionary
var road_names: PackedStringArray
var area := "Mylapore"
var vp: SubViewport
var canvas: _Canvas
var fonts := {}
var busy := false

class _Canvas extends Node2D:
	var jobs: Array = []
	var painter: SignPainter
	func _draw() -> void:
		for s in jobs: painter._paint_one(self, s)

func _ready() -> void:
	vp = SubViewport.new()
	vp.disable_3d = true
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	vp.size = Vector2i(CW * COLS, CH * 4)
	canvas = _Canvas.new()
	canvas.painter = self
	vp.add_child(canvas)
	add_child(vp)
	var f := func(file: String, wght := 0, fallback := ["NotoSansTamil_wdth_wght.ttf", "NotoSans_wdth_wght.ttf"]) -> Font:
		var base: FontFile = load("res://fonts/" + file)
		var fb: Array[Font] = []
		for x in fallback:
			if x != file: fb.append(load("res://fonts/" + x))
		base.fallbacks = fb
		if wght == 0: return base
		var v := FontVariation.new()
		v.base_font = base
		v.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): wght}
		return v
	fonts.baloo = f.call("BalooThambi2_wght.ttf", 800)
	fonts.baloo6 = f.call("BalooThambi2_wght.ttf", 600)
	fonts.arima = f.call("Arima_wght.ttf", 700)
	fonts.catamaran = f.call("Catamaran_wght.ttf", 800)
	fonts.hind = f.call("HindMadurai-Bold.ttf")
	fonts.kavivanar = f.call("Kavivanar-Regular.ttf")
	fonts.mukta = f.call("MuktaMalar-ExtraBold.ttf")
	fonts.meera = f.call("MeeraInimai-Regular.ttf")
	fonts.anton = f.call("Anton-Regular.ttf")
	fonts.oswald = f.call("Oswald_wght.ttf", 600)
	fonts.sans = f.call("NotoSans_wdth_wght.ttf", 600)
	fonts.serif = f.call("NotoSerif_wdth_wght.ttf", 700)

static func shop_name(nm: Dictionary, seed: int, trade: int) -> Dictionary:
	var r := Rng.new(seed ^ 0x5BD1E995)
	var t: Dictionary = nm.trades[trade]
	var pw := []
	for p in nm.prefix: pw.append(p[2])
	var pre: Array = nm.prefix[r.pick_w(pw)]
	var giv: Array = r.pick(nm.given)
	var vi := int(r.next() * t.ta.size())
	var sw := []
	for s in nm.suffix: sw.append(s[2])
	var suf: Array = nm.suffix[r.pick_w(sw)]
	var ta := " ".join([pre[0], giv[0], t.ta[vi], suf[0]].filter(func(x): return x != ""))
	var en := " ".join([pre[1], giv[1], t.en[mini(vi, t.en.size() - 1)], suf[1]].filter(func(x): return x != ""))
	return {"ta": ta, "en": en, "trade": t.id}

## paint all requested signs; returns an ImageTexture (atlas rows = ceil(n / COLS))
func paint(signs: Array) -> ImageTexture:
	while busy: await get_tree().process_frame
	busy = true
	var rows := maxi(1, ceili(signs.size() / float(COLS)))
	vp.size = Vector2i(CW * COLS, CH * rows)
	canvas.jobs = signs
	canvas.queue_redraw()
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	busy = false
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

static func _lum(c: Color) -> float:
	return 0.299 * c.r + 0.587 * c.g + 0.114 * c.b

func _fit(font: Font, text: String, max_w: float, px: int, min_px := 8) -> int:
	var s := px
	while s > min_px and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, s).x > max_w: s -= 1
	return s

func _text_c(ci: CanvasItem, font: Font, text: String, cx: float, base_y: float, px: int, col: Color, shadow := false) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	if shadow: ci.draw_string(font, Vector2(cx - w * 0.5 + 1, base_y + 1.5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, Color(0, 0, 0, 0.35))
	ci.draw_string(font, Vector2(cx - w * 0.5, base_y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, col)

static func _phone(r: Rng) -> String:
	if r.next() < 0.5: return "Ph: 044-24%d %d" % [10 + int(r.next() * 89), 1000 + int(r.next() * 8999)]
	return "Cell: 9%d%d %d" % [int(r.next() * 9), 100 + int(r.next() * 899), 10000 + int(r.next() * 89999)]

func _emblem(ci: CanvasItem, r: Rng, c: Vector2, rad: float, fg: Color, bg: Color, trade: String) -> void:
	ci.draw_circle(c, rad, bg)
	ci.draw_arc(c, rad, 0, TAU, 32, fg, 2.0, true)
	match trade:
		"tea", "mess", "biryani":
			ci.draw_rect(Rect2(c.x - rad * 0.35, c.y - rad * 0.2, rad * 0.6, rad * 0.6), fg)
			ci.draw_arc(c + Vector2(rad * 0.3, rad * 0.1), rad * 0.15, -PI * 0.5, PI * 0.5, 8, fg, 2.0)
		"medical":
			ci.draw_rect(Rect2(c.x - rad * 0.15, c.y - rad * 0.55, rad * 0.3, rad * 1.1), fg)
			ci.draw_rect(Rect2(c.x - rad * 0.55, c.y - rad * 0.15, rad * 1.1, rad * 0.3), fg)
		"jewel":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, rad * 0.6), c + Vector2(-rad * 0.55, -rad * 0.1), c + Vector2(-rad * 0.25, -rad * 0.45), c + Vector2(rad * 0.25, -rad * 0.45), c + Vector2(rad * 0.55, -rad * 0.1)]), fg)
		"mobile":
			ci.draw_rect(Rect2(c.x - rad * 0.28, c.y - rad * 0.55, rad * 0.56, rad * 1.1), fg)
			ci.draw_rect(Rect2(c.x - rad * 0.2, c.y - rad * 0.42, rad * 0.4, rad * 0.75), bg)
		_:
			var g: String = r.pick(["ஸ்ரீ", "ௐ", "★", "அ"])
			_text_c(ci, fonts.baloo, g, c.x, c.y + rad * 0.4, int(rad * 1.1), fg)

func _paint_one(ci: CanvasItem, s: Dictionary) -> void:
	var cell: int = s.cell
	var x0 := float(cell % COLS) * CW; var y0 := float(cell / COLS) * CH
	var r := Rng.new(int(s.seed) ^ 0x2545F491)
	var nm := shop_name(names, int(s.seed), int(s.trade))
	var trade: Dictionary = names.trades[int(s.trade)]
	var road := road_names[int(s.road)] if int(s.road) >= 0 and int(s.road) < road_names.size() else ""
	var addr := "No.%d%s, %s, Ch-4" % [1 + int(r.next() * 180), (", " + road) if road != "" else "", area]
	ci.draw_set_transform(Vector2(x0, y0))
	if s.kind == "flex":
		var bg := Color(trade.colors[0]) if trade.has("colors") and r.next() < 0.6 else Color(r.pick(names.flexColors))
		var light := _lum(bg) > 0.6
		var fg := Color(trade.colors[1]) if trade.has("colors") and r.next() < 0.6 else (Color(r.pick(["#c62828", "#1a237e", "#1b5e20", "#111111"])) if light else Color(r.pick(["#ffffff", "#ffeb3b", "#fff59d"])))
		var top := bg.lightened(0.12); var bot := bg.darkened(0.2)
		ci.draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(CW, 0), Vector2(CW, CH), Vector2(0, CH)]), PackedColorArray([top, top, bot, bot]))
		# swoosh band
		var sw := PackedVector2Array([Vector2(0, CH * 0.7)])
		for q in 9: sw.append(Vector2(CW * q / 8.0, CH * (0.7 - 0.22 * sin(PI * q / 8.0) + 0.05 * q / 8.0)))
		sw.append_array([Vector2(CW, CH), Vector2(0, CH)])
		ci.draw_colored_polygon(sw, Color(0, 0, 0, 0.08) if light else Color(1, 1, 1, 0.12))
		var em := r.next() < 0.75
		var left := CH * 0.86 if em else 8.0
		if em: _emblem(ci, r, Vector2(CH * 0.44, CH * 0.42), CH * 0.3, fg, bg.darkened(0.3), nm.trade)
		var cx := (left + CW - 6) * 0.5; var max_w := CW - left - 10
		var tfont: Font = r.pick([fonts.baloo, fonts.baloo, fonts.mukta, fonts.catamaran])
		var ta_px := _fit(tfont, nm.ta, max_w, 30)
		_text_c(ci, tfont, nm.ta, cx, 6 + ta_px * 0.95, ta_px, fg, true)
		var en_px := _fit(fonts.anton, nm.en, max_w, 19)
		_text_c(ci, fonts.anton, nm.en, cx, 10 + ta_px + en_px * 0.9, en_px, Color(0.13, 0.13, 0.13) if light else Color(1, 1, 1))
		var line := ("%s  %s" % [addr, _phone(r)]).substr(0, 64)
		var a_px := _fit(fonts.sans, line, CW - 8, 9, 6)
		_text_c(ci, fonts.sans, line, CW * 0.5, CH - 4, a_px, Color(0.2, 0.2, 0.2) if light else Color(1, 1, 1, 0.9))
	elif s.kind == "paint":
		var bg := Color(r.pick(names.paintColors))
		var light := _lum(bg) > 0.55
		ci.draw_rect(Rect2(0, 0, CW, CH), bg)
		var fg := Color(r.pick(["#b71c1c", "#0d47a1", "#1b5e20", "#212121", "#4a148c"])) if light else Color(r.pick(["#ffffff", "#ffe082", "#fff8e1"]))
		ci.draw_rect(Rect2(5, 5, CW - 10, CH - 10), fg, false, 3.0)
		if r.next() < 0.5: ci.draw_rect(Rect2(9, 9, CW - 18, CH - 18), fg, false, 1.0)
		var tfont: Font = r.pick([fonts.arima, fonts.catamaran, fonts.hind, fonts.kavivanar, fonts.meera])
		var ta_px := _fit(tfont, nm.ta, CW - 24, 28)
		_text_c(ci, tfont, nm.ta, CW * 0.5, 8 + ta_px * 0.95, ta_px, fg)
		var en_px := _fit(fonts.serif, nm.en, CW - 24, 17)
		_text_c(ci, fonts.serif, nm.en, CW * 0.5, 12 + ta_px + en_px * 0.9, en_px, fg.darkened(0.2) if light else fg)
	else:
		var u: Dictionary = names.upper[int(s.get("upper", 0)) % names.upper.size()]
		var bg := Color(r.pick(names.flexColors))
		var light := _lum(bg) > 0.6
		ci.draw_rect(Rect2(0, 0, CW, CH), bg)
		var fg := Color("#1a237e") if light else Color(1, 1, 1)
		var given: Array = r.pick(names.given)
		var t1 := "%s %s" % [given[0], u.ta]; var t2 := "%s %s" % [given[1], u.en]
		var p1 := _fit(fonts.baloo, t1, CW - 16, 26)
		_text_c(ci, fonts.baloo, t1, CW * 0.5, 6 + p1 * 0.95, p1, fg)
		var p2 := _fit(fonts.oswald, t2, CW - 16, 18)
		_text_c(ci, fonts.oswald, t2, CW * 0.5, 12 + p1 + p2 * 0.9, p2, fg)
		_text_c(ci, fonts.sans, _phone(r), CW * 0.5, CH - 5, 10, fg)
	# weathering: dust, fading, stains (hand-painted boards weather more)
	var w_amt := 0.25 + r.next() * 0.35 if s.kind == "paint" else r.next() * 0.25
	for i in 18:
		var dc := Color(0.35, 0.31, 0.24) if r.next() < 0.5 else Color(1, 0.98, 0.92)
		dc.a = r.next() * w_amt * 0.35
		ci.draw_rect(Rect2(r.next() * CW, r.next() * CH, 8 + r.next() * 60, 3 + r.next() * 20), dc)
	if s.kind == "paint":
		for i in 4:
			ci.draw_rect(Rect2(r.next() * CW, CH * 0.6, 2 + r.next() * 3, CH * 0.4), Color(0.43, 0.24, 0.08, 0.15 * w_amt + r.next() * 0.1))
	ci.draw_set_transform(Vector2.ZERO)
