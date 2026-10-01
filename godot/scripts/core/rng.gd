class_name Rng
extends RefCounted
## Deterministic PRNG (mulberry32), bit-compatible with the three.js prototype (src/engine/rng.ts),
## so a building seed produces the same choices in both. Everything in the world derives from seeds.

const M32 := 0xFFFFFFFF
var a: int

func _init(seed: int = 1) -> void:
	a = seed & M32

static func imul(x: int, y: int) -> int:
	return ((x & M32) * (y & M32)) & M32

func next() -> float:
	a = (a + 0x6D2B79F5) & M32
	var t := imul(a ^ (a >> 15), 1 | a)
	t = ((t + imul(t ^ (t >> 7), 61 | t)) & M32) ^ t
	return float((t ^ (t >> 14)) & M32) / 4294967296.0

func range_f(lo: float, hi: float) -> float:
	return lo + (hi - lo) * next()

func range_i(lo: int, hi_incl: int) -> int:
	return lo + int(next() * float(hi_incl - lo + 1)) % (hi_incl - lo + 1)

func chance(p: float) -> bool:
	return next() < p

func pick(arr: Array):
	return arr[int(next() * arr.size()) % arr.size()]

## index chosen with probability proportional to weights
func pick_w(weights: Array) -> int:
	var total := 0.0
	for w in weights: total += float(w)
	var t := next() * total
	for i in weights.size():
		t -= float(weights[i])
		if t <= 0.0: return i
	return weights.size() - 1

func seed_int() -> int:
	return int(next() * 4294967295.0)

static func hash32(n: int) -> int:
	n = n & M32
	n = (n ^ 61) ^ (n >> 16)
	n = imul(n, 9)
	n ^= n >> 4
	n = imul(n, 0x27D4EB2D)
	n ^= n >> 15
	return n & M32

static func hashf(n: int) -> float:
	return float(hash32(n)) / 4294967296.0

static func hash2(x: int, y: int) -> float:
	return hashf(imul(x, 73856093) ^ imul(y, 19349663))

## sRGB hex ("#rrggbb") to a linear Color (vertex colours are fed to shaders in linear space)
static func hex_lin(h: String) -> Color:
	return Color(h).srgb_to_linear()
