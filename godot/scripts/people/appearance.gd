class_name Appearance
extends RefCounted
## Realistic South Indian dress and skin-tone distribution (STYLE_BIBLE §6). Skin tones span
## wheatish to deep brown with no correlation to role, wealth or virtue (no colourism).
## Port of src/crowd/appearance.ts. Colours are sRGB hex; convert where needed.

const SKIN := ["#c99c78", "#b98a63", "#ab7b55", "#9c6c48", "#8c5e3e", "#7c5034", "#6b442c", "#5b3925", "#4d3020"]
const SKIN_W := [5, 10, 15, 18, 17, 14, 10, 7, 4]
const HAIR := ["#120e0c", "#1a1310", "#211813", "#0d0b0a"]
const HAIR_GREY := ["#8a8580", "#b5b0aa", "#d8d4ce", "#5c5650"]
const SHIRTS := ["#f2f0ea", "#e9eef2", "#a9c4de", "#7fa2c8", "#5a6f8c", "#7a2e35", "#2f3e5c", "#8c8c86", "#6b7a4a", "#c9b48a", "#d9c8a6", "#3d6b72", "#b85c3c", "#e0d36a", "#4f7f5b", "#9a4f80", "#262626", "#cfdbe6"]
const TSHIRTS := ["#d93636", "#2b6fd6", "#f2c230", "#1b1b1b", "#f5f5f5", "#2e9e6a", "#ff7a2f", "#7e57c2", "#00a3b4", "#e94b8a"]
const PANTS := ["#1f2533", "#2b2b2b", "#474b52", "#6e6450", "#3c4f73", "#2f4a6b", "#5a4b3a", "#4a5a6a"]
const VESHTI := ["#f4f1e8", "#efe9d8", "#f7f5ef", "#e8e0c8"]
const VESHTI_BORDER := ["#c9a43a", "#1f6b3a", "#1d3f8a", "#8a1c2a", "#d4b04a"]
const LUNGI := ["#2a4f8f", "#7b1f2d", "#2f6d47", "#4b3b7a", "#8f5a1f", "#1f5e6e", "#6d2a5b"]
const SAREES := ["#c2185b", "#e6a91c", "#7cb342", "#00838f", "#c62828", "#ef6c00", "#6a1b9a", "#1565c0", "#ad1457", "#558b2f", "#f9a825", "#4e342e", "#00695c", "#d84315", "#283593", "#9e9d24", "#b71c1c", "#ff8f00"]
const SAREE_BORDER := ["#d4af37", "#c9a43a", "#b71c1c", "#1b5e20", "#0d47a1", "#4a148c", "#e8c766"]
const KURTA := ["#f8bbd0", "#b2dfdb", "#fff59d", "#ce93d8", "#80cbc4", "#ffab91", "#90caf9", "#c5e1a5", "#f48fb1", "#e57373", "#4db6ac", "#ffd54f", "#9575cd"]
const LEGGINGS := ["#fafafa", "#212121", "#e0e0e0", "#c2185b", "#1a237e", "#004d40"]
const UNIFORM_SHIRT := ["#f5f5f5", "#e3f2fd", "#fff8e1"]
const UNIFORM_LOWER := ["#1a2a5a", "#5d1a1a", "#2e4a2e", "#3b5a8a", "#4a4a4a"]
const JASMINE := "#f6f3e6"

var variant := "man_pants"  # man_pants, man_veshti, man_lungi, woman_saree, woman_churidar, child
var sex := "m"
var scale := 1.0
var elder := false
var skin := Color()
var hair := Color()
var top := Color()
var lower := Color()
var border := Color()
var accent := Color()
var drape := Color()
var pattern := 0        # 0 plain, 1 checks, 2 border band, 3 stripes
var top_pattern := 0
var gait := 1.0
var mustache := false
var towel := false
var jasmine := false

static func make(r: Rng, demo := {"men": 0.52, "women": 0.38, "children": 0.1, "elders": 0.16, "traditional": 0.45}) -> Appearance:
	var a := Appearance.new()
	var kind := r.pick_w([demo.men, demo.women, demo.children])
	a.elder = kind != 2 and r.next() < demo.elders
	a.skin = Color(SKIN[r.pick_w(SKIN_W)])
	a.hair = Color(r.pick(HAIR_GREY)) if a.elder and r.next() < 0.7 else Color(r.pick(HAIR))
	a.gait = 0.75 if a.elder else 1.0
	if kind == 0:
		a.sex = "m"
		a.scale = 0.97 + r.next() * 0.1
		a.mustache = r.next() < 0.6
		var trad: bool = r.next() < demo.traditional + (0.3 if a.elder else 0.0)
		if trad:
			if r.next() < 0.55:
				a.variant = "man_veshti"; a.lower = Color(r.pick(VESHTI)); a.border = Color(r.pick(VESHTI_BORDER)); a.pattern = 2
			else:
				a.variant = "man_lungi"; a.lower = Color(r.pick(LUNGI)); a.border = Color(r.pick(LUNGI)); a.pattern = 1
			a.top = Color(r.pick(SHIRTS)) if r.next() < 0.75 else Color(r.pick(VESHTI))
			a.top_pattern = 1 if r.next() < 0.25 else 0
			a.towel = r.next() < 0.35
		else:
			a.variant = "man_pants"
			a.top = Color(r.pick(TSHIRTS)) if r.next() < 0.4 else Color(r.pick(SHIRTS))
			a.top_pattern = 1 if r.next() < 0.2 else (3 if r.next() < 0.1 else 0)
			a.lower = Color(r.pick(PANTS))
	elif kind == 1:
		a.sex = "f"
		a.scale = 0.92 + r.next() * 0.08
		a.jasmine = r.next() < 0.5
		if r.next() < demo.traditional + 0.3 + (0.3 if a.elder else 0.0):
			a.variant = "woman_saree"
			a.lower = Color(r.pick(SAREES)); a.drape = a.lower
			a.top = Color(r.pick(SAREES)) if r.next() < 0.6 else a.lower
			a.pattern = 2; a.border = Color(r.pick(SAREE_BORDER))
		else:
			a.variant = "woman_churidar"
			a.top = Color(r.pick(KURTA)); a.lower = Color(r.pick(LEGGINGS))
			a.drape = Color(r.pick(KURTA)) if r.next() < 0.5 else a.lower
			a.top_pattern = 3 if r.next() < 0.3 else 0
	else:
		a.variant = "child"; a.scale = 0.62 + r.next() * 0.2; a.gait = 1.2
		a.sex = "m" if r.next() < 0.5 else "f"
		if r.next() < 0.6:
			a.top = Color(r.pick(UNIFORM_SHIRT)); a.lower = Color(r.pick(UNIFORM_LOWER))
		else:
			a.top = Color(r.pick(TSHIRTS)); a.lower = Color(r.pick(PANTS))
	return a
