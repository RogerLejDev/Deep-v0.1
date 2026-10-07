class_name GameConfig
extends RefCounted
## Global, compile-time tuning constants for DEEP.
## Nothing here is mutable at runtime: gameplay balance lives in data/ resources.

# --- Spatial units -----------------------------------------------------------
const TILE_SIZE: int = 16
const CHUNK_TILES: int = 32
const CHUNK_PX: int = TILE_SIZE * CHUNK_TILES

## World is finite. Width is bounded by bedrock walls, depth by the core shell.
const WORLD_TILES_X: int = 384
const WORLD_TILES_Y: int = 704

## Tile row that represents 0 m. Everything above is sky.
const SURFACE_ROW: int = 64
## One tile of descent in in-game metres. 0.5 keeps 300 m a real expedition.
const METRES_PER_TILE: float = 0.5

const CHUNKS_X: int = WORLD_TILES_X / CHUNK_TILES
const CHUNKS_Y: int = WORLD_TILES_Y / CHUNK_TILES

# --- Streaming ---------------------------------------------------------------
## Chunks kept live around the player (radius in chunks).
const CHUNK_LOAD_RADIUS_X: int = 2
const CHUNK_LOAD_RADIUS_Y: int = 2
## Extra ring kept in memory before being released, avoids thrash when pacing.
const CHUNK_KEEP_RADIUS: int = 1
## Max chunks meshed per frame. Keeps hitches off mid-range phones.
const CHUNK_BUILDS_PER_FRAME: int = 1

# --- Player ------------------------------------------------------------------
const PLAYER_WALK_SPEED: float = 118.0
const PLAYER_RUN_SPEED: float = 176.0
const PLAYER_ACCEL: float = 1300.0
const PLAYER_FRICTION: float = 1500.0
const PLAYER_AIR_CONTROL: float = 0.55
const PLAYER_JUMP_VELOCITY: float = -332.0
const PLAYER_MAX_FALL: float = 620.0
const COYOTE_TIME: float = 0.10
const JUMP_BUFFER: float = 0.12
## Terminal-velocity falls hurt below this impact speed.
const FALL_DAMAGE_THRESHOLD: float = 540.0

## Mining reach, in tiles, measured from the player's centre.
const MINING_REACH_TILES: float = 4.2
const PLACE_REACH_TILES: float = 4.2

# --- Creatures ---------------------------------------------------------------
## Hard cap on simultaneously simulated creatures. Mobile budget.
const MAX_ACTIVE_CREATURES: int = 22
const CREATURE_SPAWN_INTERVAL: float = 1.4
## Creatures beyond this distance (px) from the player are released.
const CREATURE_DESPAWN_DISTANCE: float = 980.0
## Creatures beyond this distance stop running full AI and idle cheaply.
const CREATURE_SLEEP_DISTANCE: float = 560.0

# --- Codex -------------------------------------------------------------------
## Planned size of the finished archive. V0.1 ships a subset; the Codex UI is
## explicit about how many slots are actually catalogued in this build.
const CODEX_PLANNED_SLOTS: int = 250
## Observation seconds needed to fully resolve one species' entry.
const OBSERVATION_FULL: float = 9.0

# --- Ecology -----------------------------------------------------------------
## Seconds of play before a depleted region starts recovering.
const ECOLOGY_TICK_SECONDS: float = 20.0
const ORE_REGROW_SECONDS: float = 420.0

# --- Save --------------------------------------------------------------------
const SAVE_SLOTS: int = 3
const AUTOSAVE_SECONDS: float = 45.0
const SAVE_FORMAT_VERSION: int = 1

# --- Helpers -----------------------------------------------------------------

static func tile_to_world(tx: int, ty: int) -> Vector2:
	return Vector2(float(tx * TILE_SIZE), float(ty * TILE_SIZE))

static func tile_centre(tx: int, ty: int) -> Vector2:
	return Vector2(
		float(tx * TILE_SIZE) + TILE_SIZE * 0.5,
		float(ty * TILE_SIZE) + TILE_SIZE * 0.5
	)

static func world_to_tile(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / float(TILE_SIZE)), floori(p.y / float(TILE_SIZE)))

static func tile_to_chunk(t: Vector2i) -> Vector2i:
	return Vector2i(floori(float(t.x) / CHUNK_TILES), floori(float(t.y) / CHUNK_TILES))

## Depth in metres for a world position. Negative above the surface line.
static func depth_metres(p: Vector2) -> float:
	return (p.y / float(TILE_SIZE) - float(SURFACE_ROW)) * METRES_PER_TILE

static func metres_to_world_y(m: float) -> float:
	return (m / METRES_PER_TILE + float(SURFACE_ROW)) * float(TILE_SIZE)

static func in_bounds(tx: int, ty: int) -> bool:
	return tx >= 0 and ty >= 0 and tx < WORLD_TILES_X and ty < WORLD_TILES_Y
