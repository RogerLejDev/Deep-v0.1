class_name RngUtil
extends RefCounted
## Stateless integer hashing.
##
## Worldgen must be reproducible without carrying an RNG cursor around, so
## every "random" decision in generation is a hash of (seed, coords, salt)
## instead of a draw from a stream. These are plain 32-bit mixes
## (Wang / xxHash-style finalisers) and are stable across platforms because
## everything stays inside int64 with explicit masking.

const MASK: int = 0xFFFFFFFF


static func mix(x: int) -> int:
	var h := x & MASK
	h = (h ^ (h >> 16)) & MASK
	h = (h * 0x7FEB352D) & MASK
	h = (h ^ (h >> 15)) & MASK
	h = (h * 0x846CA68B) & MASK
	h = (h ^ (h >> 16)) & MASK
	return h


static func hash2(a: int, b: int) -> int:
	return mix(((a & MASK) * 0x9E3779B1 + (b & MASK) * 0x85EBCA77) & MASK)


static func hash3(a: int, b: int, c: int) -> int:
	var h := ((a & MASK) * 0x9E3779B1) & MASK
	h = (h + ((b & MASK) * 0x85EBCA77)) & MASK
	h = (h + ((c & MASK) * 0xC2B2AE3D)) & MASK
	return mix(h)


static func hash4(a: int, b: int, c: int, d: int) -> int:
	return mix((hash3(a, b, c) + ((d & MASK) * 0x27D4EB2F)) & MASK)


## Hash -> [0, 1).
static func to_unit(h: int) -> float:
	return float(h & MASK) / 4294967296.0


## Hash -> [-1, 1).
static func to_signed(h: int) -> float:
	return to_unit(h) * 2.0 - 1.0


static func range_int(h: int, from: int, to_exclusive: int) -> int:
	if to_exclusive <= from:
		return from
	return from + int(to_unit(h) * float(to_exclusive - from))


## Deterministic RandomNumberGenerator for a named sub-system.
static func stream(world_seed: int, salt: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash2(world_seed, salt.hash())
	return rng
