# GTIndian — project memory

An open-world crime game set in an authentic South India (Chennai first). Native **Godot 4.7** (Forward+, Metal on the Mac). The full brief is in `BRIEF.md`; the roadmap is in `docs/PLAN.md`; the session log and next steps are in `docs/PROGRESS.md`. **Read `docs/PROGRESS.md` first every session.**

Repo: https://github.com/Aweswomedude1234/GTChennai. Dev machine: MacBook Air M5, 24 GB. The browser-only requirement and the 20 s load target are dropped (2026-10-01). The old three.js prototype in `src/` is reference only and no longer runs (its data moved to `godot/packs/`).

## Stack
Godot 4.7.2 stable · GDScript · Forward+ renderer · Jolt physics · custom `.gdshader` materials with procedural, tileable textures · offline tools in Python (numpy) and Node.

## Commands
- `tools/godot.sh` — play (finds Godot via `$GODOT`, `/Applications/Godot.app`, or PATH). `tools/godot.sh --editor` opens the editor.
- `tools/godot.sh --headless --import` — (re)import assets and refresh the class cache after adding scripts.
- `tools/check.sh` — parse-check every GDScript file.
- `tools/shots.sh <set> [--only=a,b] [--res=1600x900] [--quality=…]` — screenshot harness: renders the shots in `godot/harness/shots.json` to `docs/screens/<set>/` plus `report.json`. Shots can `snap` to the nearest road, or run tests (`"test": "scene"` spawns the player and parked vehicles; `"test": "drive"` autopilots a vehicle across streamed chunks and records streaming stats). On headless Linux it uses Xvfb + Mesa lavapipe (software Vulkan, ~1 fps — fine for stills).
- `tools/godot.sh --resolution 800x450 res://scenes/studio.tscn -- --studio=human,auto,bike,car` — asset studio contact sheets in `docs/screens/studio/`.
- `python3 tools/textures/gen.py [--only name]` — regenerate the procedural tileable textures in `godot/textures/`.
- `python3 tools/fonts/fetch.py` — fetch OFL fonts (full TTFs) into `godot/fonts/`.
- Blender pipelines (run with a Python that has `bpy`, e.g. `/home/claude/bpyenv/bin/python`; reimport afterwards): `tools/humans/build_humans.py` (MPFB bodies + MakeHuman assets), `tools/humans/build_anims.py` (CMU mocap + IK riding poses), `tools/humans/bake_vat.py` (crowd VAT), `tools/vehicles/build_vehicles.py [--only kind]`, `tools/animals/build_animals.py`.
- `python3 tools/audio/gen.py` — synthesise the placeholder sound set into `godot/audio/`.
- `node tools/osm/fetch.mjs` then `node tools/osm/build.mjs` — Overpass → `godot/packs/<city>/regions/<id>/`.

## Game args (after `--`)
Any settings key (`--quality=low|medium|high|ultra`, `--camera=third|first|top`, `--city=…`, `--near_r=`, `--far_r=`) plus `--hour=17.5`, `--freeze`, `--wet=1`, `--spawn=x,z`, `--shot=<set>`, `--only=a,b`, `--nocrowd`, `--notraffic`, `--noanimals`, `--nosound`, `--lowmem` (harness on lavapipe: capped near tiers, no TAA).

## Controls
WASD move / drive · Shift sprint · Alt walk · Space jump / handbrake · F enter/exit vehicle · C cycle camera (third/first/top) · H horn · V look back · [ ] time −/+ 1 h · F3 debug overlay · Esc release mouse. Gamepad mapped (sticks, triggers for throttle/brake).

## Layout (`godot/`)
- `scripts/core/` — `settings.gd` (autoload `Settings`, input map, cmdline args), `rng.gd` (mulberry32, bit-compatible with the prototype)
- `scripts/world/` — `city_pack.gd` (pack + region data, road queries), `region_builder.gd` (ground, roads, footpaths, tanks, beach, sea), `building_gen.gd` (procedural buildings, threaded), `sign_painter.gd` (Tamil+English sign atlases via SubViewport), `streamer.gd` (near/far chunk rings, WorkerThreadPool), `street_detail.gd` (street furniture), `sky_clock.gd` (day/night, fog, globals), `mats.gd`, `mb.gd` (mesh builder), `world.gd`
- `scripts/player/`, `scripts/camera/` (`camera_rig.gd`: third/first/top), `scripts/vehicles/` (`vehicle.gd` raycast physics, `vehicle_defs.gd` tuning, `vehicle_model.gd` Blender bodies + per-instance paint, `traffic.gd` kinematic traffic with near/far tiers and riders, `autopilot.gd`, `vehicle_spawner.gd`), `scripts/people/` (`human_actor.gd` MPFB/MakeHuman bodies + mocap, `crowd.gd` pedestrians + VAT tier, `animals.gd` dogs/cows/goats, `appearance.gd`), `scripts/world/soundscape.gd` (ambience, engines, horns), `scripts/ui/hud.gd`, `scripts/harness/harness.gd`, `scripts/tools/` (`studio.gd`, `traffic_test.gd`, `mesh_stats.gd`)
- `shaders/` — `facade` (cells with parallax interiors), `generic` (props, typed by CUSTOM0.x), `road`, `ground`, `sign`, `sea`, `water`, `sky`, `common.gdshaderinc`
- `packs/<city>/` — city data packs (pack.json, style.json, names.json, regions); `textures/`, `fonts/`, `harness/shots.json`
- Repo root: `tools/` (offline pipelines), `data/`, `docs/` (PLAN, PROGRESS, DECISIONS, BLOCKERS, PLACEHOLDERS, CREDITS, STYLE_BIBLE, screens/)

## Conventions
- World units are metres. x = east, z = south, y = up (same as the data). Godot nodes face −Z: a heading `h` from the data (faces (sin h, cos h)) maps to `rotation.y = atan2(-dx, -dz)` of that direction.
- Footprints from OSM: outward edge normal = (dz, −dx). Godot front faces are clockwise; `MB.quad()` takes the intended normal and fixes winding itself.
- Vertex layout: COLOR = linear albedo, UV, CUSTOM0/CUSTOM1 = per-material data (see shader headers). Global shader uniforms: `night`, `hour`, `wet`, `power`, `wind` (project.godot `[shader_globals]`).
- GDScript: give explicit types when the value comes from a Dictionary/Array (`var x: float = d.w`) — `:=` inference fails on Variants.
- glTF flips V: data packed into UV2 in Blender reads back as `1 - v` in Godot shaders.
- Everything is deterministic from seeds (OSM way id → building seed). No real brands, parties or politicians (fictional parties TMEK and ATM, STYLE_BIBLE §10). No paid/external AI asset services.
- Commit as Aweswomedude1234 with the Co-Authored-By Claude trailer.
