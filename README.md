# DEEP — V0.1

**GO DEEPER. FIND LIFE.**

A 2D subterranean exploration / excavation / creature-collection game for mobile,
built in **Godot 4.7.2** with **GDScript**. Landscape, touch-first, and entirely
offline: no server, no account, no network calls, no cloud. Saves are local files.

This is a vertical slice. It is meant to be played for 15–30 minutes and to make
you want to keep going down. Everything listed under *What actually works* is
implemented and verified — nothing in this build is a mock-up.

---

## Running it

**In the editor**

```
godot --path . # or open project.godot in Godot 4.7.2
```

**Desktop test build**

```
godot --path . --rendering-driver opengl3
```

**Test suite** (916 assertions, headless, no GPU needed)

```
godot --headless --path . res://tests/TestRunner.tscn
```

Exits non-zero on failure, so it can gate a build.

**Screenshot pass** (renders the title screen, each depth band, the creatures
and every panel to `user://shots/`)

```
godot --path . --rendering-driver opengl3 res://tools/Capture.tscn
```

**Android**: the project is configured for the GL Compatibility renderer,
landscape orientation and `canvas_items` stretch at a 1280×720 base, which is
what an Android export needs. The export preset itself is not committed because
it would carry machine-specific SDK and keystore paths — add one in
*Project → Export* and it will build as-is.

---

## Controls

Touch is the primary input; keyboard and mouse work too, so the game is testable
on a desktop.

| Action | Touch | Keyboard / mouse |
|---|---|---|
| Move | Left stick (the whole left third of the screen is the stick zone; it re-centres under your thumb) | `A` / `D` or arrows |
| Run | Push the stick past half deflection | Held automatically while a key is down |
| Jump | `▲` button | `Space` |
| Mine | Tap a tile to target it, then **hold** `⛏` | Hold left mouse on a tile |
| Place block | `＋` button (select what to place in the pack first) | Right mouse |
| Interact | `✦` button, near a base-camp station | `E` |
| Pack | `PACK` chip | `I` |
| Crafting | `CRAFT` chip | `K` |
| Codex | `CODEX` chip | `C` |
| Pause | `☰` chip | `Esc` |
| Debug overlay | Five quick taps in the top-left corner | `F3` |

Holding `⛏` with nothing targeted auto-aims at the tile in front of you, then
below you — so one thumb is enough to dig forward and dig down.

---

## What actually works

**World**
- Seed-driven procedural generation. The same seed always rebuilds the same
  world; the seed is typeable on the title screen (text is hashed, so
  `rootlands` is a valid world).
- 384 × 704 tiles, finite and bounded by a bedrock shell. Chunked at 32×32 with
  a live window around the player; chunk data is LRU-cached and released.
- Caves from a two-field noise intersection (long connected tunnels, not blobs),
  large caverns below 120 m, and a guaranteed cave mouth near spawn so the first
  minute always has somewhere to go.
- Three deterministic structure types: root hollows, crystal chambers and
  ancient vaults.
- 18 materials with depth-banded ore and crystal pockets.

**Destructible terrain**
- Every tile can be mined and most can be placed. Collision is rebuilt from
  merged rectangles (a solid chunk becomes one box, not 1024).
- `WORLD BASE` and `PLAYER MODIFICATIONS` are stored separately. Saves contain
  only the seed plus your edits, so a save file stays small no matter how much
  you dig.

**Mining and progression**
- Four picks with real differences in speed *and* in what they can touch:
  Scrap → Copper → Iron → Lumen. Deepstone, iron, crystal, compressed rock and
  ancient masonry are each gated behind a tier, so each tool opens a stratum.
- Per-tile break progress, a corner-bracket reticle with a progress ring, chips,
  dust, debris, screen shake and material-specific audio.

**Inventory and crafting**
- 24-slot pack with stacking, splitting, merge-on-move and a tap-tap move
  interaction (no drag needed). A 30-slot chest at base camp.
- Eight data-driven recipes across tools, gear, light, building and survival.
  Bench recipes require the base workbench; field recipes do not.

**Creatures**
- Six species, defined entirely in `data/creatures/*.json` plus one SVG each:
  Grib, Molo, Glowling, Kryx, Aberrant, Lumreaper.
- Six behaviour profiles — skittish, burrower, drifter, aggressive, phantom,
  apex — with real distinct logic. Molo genuinely chews through soft rock and
  leaves the side passages you later find; Glowlings retreat from light; Kryx
  guard crystal seams and leash back to them; the Aberrant dissolves when hurt
  and reappears elsewhere.
- 17 variants across the six species, each a recolour plus stat multipliers,
  weighted so rare ones stay rare.
- Population pressure: over-hunting a region visibly thins that species there
  for a while, then it recovers.

**Codex**
- *Seeing is not knowing.* A sighting opens an entry and reveals its name and
  art. Habitat, behaviour, diet, resource, weakness and the narrative note each
  unlock only after enough **observation time** — which only accrues while the
  creature is alive, on screen, and lit well enough to identify.
- That makes the lantern a progression item: in the deep strata you cannot
  complete entries you cannot light up.
- Unknown species show as numbered silhouettes. Variants are tracked separately
  and shown as their own collectables.
- A staged full-screen `NEW DISCOVERY` reveal with time dilation, expanding
  rings, particles, the silhouette resolving into the real art and the name
  typing in. Legendaries get a louder version of the same.

**The legendary system**
- The apex species is on no spawn table at all. It arrives through an
  `UNKNOWN SIGNAL` event gated on depth, darkness, how long you have stayed
  down this expedition, a long cooldown and then a small roll — so a region can
  read 100% complete and still, hours later, produce something you have never
  seen. It is probability-gated, never scripted, so it cannot be farmed.
- The Lumreaper itself is a three-phase encounter (hunt → flare → exposed) with
  a real vulnerability window, a boss bar and a phase readout.

**Survival and expeditions**
- Fall damage, contact damage, light as a resource, and a death rule tuned for
  tension without frustration: **half of your resources** stay where you fell in
  a visible, collectable cache. Tools, gear, the Codex, the depth record and all
  progression come back with you. A death costs a trip, not a run.

**A living region**
- Mined-out ore veins regrow after a cooldown; tunnels you dug never do. The
  separation is explicit — only resource overrides are allowed to expire.

**Saves**
- Three local slots, atomic writes (temp file + verify + rename), one generation
  of backup, a payload checksum and schema validation. A damaged slot falls back
  to its backup; an unreadable one is reported rather than crashing.
- Autosave every 45 s, on pause, at the save beacon, and on Android focus-out.

**Presentation**
- Terrain is a single draw call per chunk through a custom shader: per-tile
  value jitter, world-space multi-octave grain, cracks, mineral speckle,
  organic/crystalline material treatments, per-tile seams and lit top faces,
  contact shadows, and a noise-frayed silhouette so nothing reads as a clean
  grid.
- Lighting is a custom 2D model: one shared 16-light texture that terrain,
  creatures, props and haze all sample, so nothing pops when it crosses a light
  boundary and ambient darkness can deepen without dimming the lights.
- Procedural parallax backdrop (sky, sun, drifting cloud, three ridge layers
  above ground; strata, cavern voids, stalactites and distant crystal glints
  below), depth haze that light burns through, floating motes, camera
  look-ahead and trauma-based shake.
- All art is SVG — six creatures, four player parts, four props, one icon —
  rasterised at the exact pixel size each sprite needs and recoloured per
  variant in HSV, so gradients survive. Item icons are generated as SVG markup
  from a shape family plus a palette, which is why adding a resource needs no
  art.
- All audio is synthesised at boot into PCM buffers: mining, breaking, crystal
  shatter, pickup, craft, jump, land, hurt, UI, the discovery sting, creature
  chirps, and three seamless depth-keyed ambience loops.

**Debug mode** — off by default, never required. Shows FPS, memory, seed,
position, tile, chunk, depth, state, mining target, zone, ambient value, live
light count, live chunks, modification count, pending regrowth, creature and
observation counts and the rare-event timers; plus teleport-to-depth, give kit,
spawn any species, unlock the Codex, force the rare event, and heal.

---

## The first 30 minutes

0–5 min — arrive at the base camp, walk, dig, find dirt, stone and your first
copper. 5–10 min — reach the workbench, craft a **Copper Pick**, and feel stone
stop being a wall. Meet a Grib; it runs. 10–20 min — follow the cave mouth down
past 50 m. The light drops, Glowlings drift away from your lantern, a Kryx
charges you off a crystal seam. First Codex entries. 20–30 min — craft the
**Iron Pick** and the **Deep Lantern**, cross 150 m into the deep strata, and
find worked stone that something cut a very long time ago.

---

## Decisions I made, and why

- **A custom light texture instead of `Light2D` nodes.** `CanvasModulate`
  darkens the light passes along with everything else, which makes a dark cave
  with a bright lamp impossible. One shared 16×2 texture read by every lit
  shader fixes that, gives terrain and creatures identical lighting, and costs
  one write per frame instead of one per material.
- **Hash-based worldgen, not a seeded RNG stream.** Every generation decision is
  a hash of (seed, coordinates, salt), so `block_at` is a pure function and
  chunks can be generated in any order. That is what makes streaming,
  regeneration and tiny save files possible.
- **Creatures as data, behaviours as named profiles.** A species is a JSON file
  and an SVG. New code is only needed for a behaviour that does not exist yet.
- **Observation instead of capture.** Capturing creatures is a large system and
  the loop needs to be proven first. Observation gives the Codex a real
  mechanic, makes light matter, and leaves room for capture later.
- **The silhouette threshold is steep.** A bilinear solidity field rounds
  corners beautifully and makes terrain unreadable as *blocks*. Steepening the
  curve keeps walls flush with the tile grid; the seams and lit top faces put
  the grid back where the player needs it.
- **Depth is 0.5 m per tile.** 300 m is then 600 tiles, which is a real descent
  rather than a short lift ride.
- **The Codex counter shows `discovered / catalogued` and states the archive
  size separately.** Showing `3 / 250` when only six entries exist would be a
  lie about what is in the build.

---

## Known limits of V0.1

These are deliberate scope cuts, not broken systems.

- **One biome.** Rootlands only, in five depth bands. Mycelium and Abyssal are
  not in this build; `BiomeTable` is written to take them (a zone row plus a
  spawn table) without touching the renderer or the spawner.
- **No map screen.** The HUD carries depth, zone and your depth record; a
  fog-of-war depth map is not implemented.
- **No capture mechanic.** Observation and the Codex only, by the reasoning
  above.
- **The Lumreaper is the only apex encounter**, and it is deliberately very hard
  to trigger (deep, dark, 75 s of dwell, a 25-minute cooldown, then a ~1.8%
  roll per check). Use the debug overlay's `SIGNAL` button to see it on demand.
- **Oxygen, heat and pressure** exist as design slots, not as systems — there is
  no water body in this build to need them. The HUD and `Game.effects` already
  have the shape for them.
- **The base camp is fixed.** No expansion, farms or laboratory yet.
- **Audio is synthesised.** It is real, tuned and tied to every event, but it is
  placeholder-grade compared to recorded foley.
- **No Android export preset is committed** (it would hardcode SDK and keystore
  paths). Everything else about the project is mobile-ready.
- **Shaders are validated by rendering, not by unit test.** The suite checks
  they load and that scenes instantiate; the screenshot pass in `tools/` is what
  catches visual regressions.

---

## Layout

```
DEEP/
├── project.godot
├── data/creatures/*.json      species definitions
├── assets/svg/                creatures, player parts, props, icon
├── shaders/                   terrain, ambient-lit sprites, haze, backdrop
│                              + shared noise and lighting includes
├── scripts/
│   ├── core/                  config, event bus, game state, audio, debug, router
│   ├── world/                 worldgen, structures, chunks, streaming, lights, ecology
│   ├── player/                movement, mining, procedural animation
│   ├── inventory/             items and the pack
│   ├── crafting/              recipes and rules
│   ├── creatures/             data, brains, spawner, rare events
│   ├── codex/                 knowledge store and observation
│   ├── save/                  slots, atomic writes, validation
│   ├── ui/                    kit, HUD, touch controls, panels, menus
│   ├── vfx/                   camera, particles, ambience
│   └── base/                  surface camp
├── scenes/                    main menu, game root
├── tests/                     headless suite
└── tools/                     screenshot harness
```
