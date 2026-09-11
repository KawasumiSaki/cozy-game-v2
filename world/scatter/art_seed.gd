class_name CozyArtSeed
extends RefCounted
## Deterministic art seed (V2.1 doc E.21).
##
##     WorldSeed + ChunkCoord + ObjectID + ArtRuleID  ->  Deterministic Seed
##
##     "相同：世界 / 位置 / 资产 Definition / 规则 必须生成相同结果。"
##     "这样存档加载不会出现：昨天这棵树在左边，今天跑到右边。"
##
## EVERY procedural visual decision routes through here. Nothing in the art path
## may touch a random source directly — one stray RandomNumberGenerator is
## enough to make the world rearrange itself across a save and reload, and that
## is precisely the failure the doc names.
##
## This is the same discipline the wall assembler follows for masonry shading;
## that one hashes (seed, row, col), this one hashes named parts.

const FNV_OFFSET := 0x811C9DC5
const MIX_A := 0x9E3779B1
const MIX_B := 0x85EBCA6B
const MIX_C := 0xC2B2AE35


## Combine any number of integers into one stable seed.
## Order matters, and identical inputs always give an identical result.
static func mix(parts: Array) -> int:
	var h := FNV_OFFSET
	for p in parts:
		var v: int = int(p)
		h = h ^ (v & 0xFFFFFFFF)
		h = (h * MIX_A) & 0x7FFFFFFF
		h = h ^ (h >> 13)
		h = (h * MIX_B) & 0x7FFFFFFF
		h = h ^ (h >> 16)
	return h


## Turn world position + a rule name into a seed. The rule name is hashed as a
## string so rules cannot accidentally collide by being passed the same integer.
static func for_cell(world_seed: int, chunk: Vector2i, cx: int, cz: int,
		rule: String) -> int:
	var h := mix4(world_seed, chunk.x, chunk.y, cx)
	return _fold(h, cz) ^ _fold(h, hash(rule))


## Seed -> a stable value in [0, 1). Use this instead of randf().
static func unit(seed_val: int) -> float:
	return float(seed_val % 1000003) / 1000003.0


## Seed -> a stable value in [lo, hi).
static func range_f(seed_val: int, lo: float, hi: float) -> float:
	return lo + unit(seed_val) * (hi - lo)


## Seed -> a stable index in [0, count).
static func pick_index(seed_val: int, count: int) -> int:
	if count <= 0:
		return 0
	return seed_val % count


## Allocation-free mix of four integers. The Array-taking `mix()` above is fine
## for occasional use, but it builds an Array literal on every call, and the
## scatter path calls this tens of thousands of times per rebuild. Measured:
## swapping the hot paths to this took the rebuild from 169 ms to single digits.
static func mix4(a: int, b: int, c: int, d: int) -> int:
	var h := FNV_OFFSET
	h = _fold(h, a)
	h = _fold(h, b)
	h = _fold(h, c)
	h = _fold(h, d)
	return h


static func _fold(h: int, v: int) -> int:
	h = h ^ (v & 0xFFFFFFFF)
	h = (h * MIX_A) & 0x7FFFFFFF
	h = h ^ (h >> 13)
	h = (h * MIX_B) & 0x7FFFFFFF
	h = h ^ (h >> 16)
	return h


## Seed -> a stable angle in radians, for scattering rotation.
static func angle(seed_val: int, steps := 8) -> float:
	var n := pick_index(seed_val, steps)
	return TAU * float(n) / float(steps)


## Deterministic smooth value noise in [0, 1).
##
## Used to carve out REGIONS — woodland, clearings — rather than to decide
## individual cells. That distinction is what makes a forest read as a place:
## per-cell scatter alone only ever produces denser speckle.
##
## Bilinear interpolation between hashed lattice points, with a smoothstep ramp
## so region boundaries are not blocky. Deterministic like everything else here:
## the same world always produces the same forest.
static func value_noise(x: float, z: float, scale: float, world_seed: int) -> float:
	if scale <= 0.0001:
		return 0.0
	var fx := x / scale
	var fz := z / scale
	var x0 := int(floor(fx))
	var z0 := int(floor(fz))
	var tx := fx - float(x0)
	var tz := fz - float(z0)

	# Smoothstep: gentler transitions than a straight lerp, so woodland fades
	# into grassland instead of ending on a straight line.
	tx = tx * tx * (3.0 - 2.0 * tx)
	tz = tz * tz * (3.0 - 2.0 * tz)

	const SALT := 0x1F0DE57
	var v00 := unit(mix4(world_seed, x0, z0, SALT))
	var v10 := unit(mix4(world_seed, x0 + 1, z0, SALT))
	var v01 := unit(mix4(world_seed, x0, z0 + 1, SALT))
	var v11 := unit(mix4(world_seed, x0 + 1, z0 + 1, SALT))

	return lerpf(lerpf(v00, v10, tx), lerpf(v01, v11, tx), tz)
