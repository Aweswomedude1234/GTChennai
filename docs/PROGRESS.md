# Progress log

> **Read this first.** Current state and next steps are at the top; history below.

## Current state (2026-10-04, session 2 — vehicles, traffic, MakeHuman humans, livelier streets)
- **Engine: Godot 4.7.2** (owner confirmed). Project in `godot/`; see CLAUDE.md for commands. Pushing to origin/main works.
- **Phase 1 (Godot) done** (tag `phase1`): city pack + region loader, ground/roads/junctions/footpaths, temple tanks, canals, beach and sea, procedural buildings with interior-mapped façades, Tamil+English sign atlases, threaded near/far streaming, horizon LOD, day/night, player, cameras, raycast vehicles, harness, asset studio.
- **Streetscape (Phase 2):** OSM plot infill, temple architecture, poles/cables/lights/trees/drains/compound walls/kolams/posters (see `street_detail.gd`). New this session: footpath **vendors** (fruit carts, flower sellers, tender-coconut heaps, tea carts, striped umbrellas) with stationary vendors and customers registered in the crowd; men with tea glasses outside tea shops; **banners and pennant strings across busy roads**; **flex hoardings** on junction corners.
- **Vehicles (new):** `tools/vehicles/build_vehicles.py` builds auto, hatch + compact sedan (call-taxi), bike, scooter and MNT bus in Blender: Catmull-Rom lofted shells (glass/pillars on exact grid rows), arches by boolean, fascia/lamps/grilles/plates/shut lines as surface-projected decals, low-detail `_lo` copies. `VehicleModel` maps materials to `vehicle.gdshader` (per-instance paint, livery band, dust, clear coat, brake/indicator/head lamps) and `vehicle_glass.gdshader`. Player vehicles and parked rows use the models.
- **Traffic (new):** `traffic.gd` — kinematic IDM agents on the OSM graph, left-hand, per-road density quotas by rank, two-wheeler/auto weaving, junction turns with indicators, U-turns at dead ends, player as obstacle (brake + honk timer). Near tier: pooled bodies with colliders and skeletal riders (IK-built `ride_*` poses from `build_anims.py`); far tier: MultiMesh low-detail bodies with VAT riders drawn by the crowd. Headless check: `godot --headless -s res://scripts/tools/traffic_test.gd`.
- **Humans:** MPFB bodies now wear **MakeHuman CC0 assets** (photo skin textures re-toned per person, card hair incl. the Tamil braid, eyebrows, eyelashes, casual shirt/jeans suits split into top/lower, shoes); shaders keep per-person colours using the textures' luminance detail. VAT crowd rebaked (riding clips included).
- **Harness on lavapipe:** memory is the limit (~6 GB cgroup). Every compiled pipeline and GPU buffer lives in RAM, so `tools/shots.sh` passes `--lowmem` (near tiers capped, TAA off). Use `--near_r=220 --far_r=800` for street shots. Expect ~15 min per 800×450 shot.
- **Next (in order):** (1) animals (stray dogs, cows, crows) and pedestrians crossing through traffic; (2) more fleet: lorry, Tata-Ace-type mini truck, bicycle, share-auto, water tanker, car/bus occupants; (3) ambience audio (traffic, horns, vendors' calls, temple bells) + spatial horns; (4) Phase 2 remaining: San Thome/Luz churches, MRTS, night lighting audit, density audit; (5) on the Mac: performance pass with the full near tiers.
- **Workspace notes:** Blender runs as `bpy` 5.2.2 in a venv (`/home/claude/bpyenv`, Pillow installed); MPFB is a Blender extension (`~/.config/blender/5.2/extensions/user_default/mpfb`); MakeHuman system assets unzipped into MPFB's user data (`~/.config/blender/5.2/extensions/.user/user_default/mpfb/data`, or set `MH_ASSETS`); CMU BVH in `/home/claude/cmu`. On the Mac: `pip install bpy`, copy MPFB into Blender's extensions folder, unzip `makehuman_system_assets_cc0.zip` into its user data.

## Handoff from session 1 (ThinkPad, three.js)

## Status at handoff (2026-10-01)

| Phase | State |
|---|---|
| 0. Foundation | **Done** (tag `phase0`) |
| 1. Core engine | **Partly done** in three.js. Paused for the engine switch below. |
| 2–10 | Not started |

### Decision pending at the start of the Mac session: engine switch
The owner wants to move off the browser stack (the 20-second load target is dropped) to get higher visual quality, using **Godot or Unity, whichever Claude can edit best**.

**Recommendation: Godot 4 (latest stable), Forward+ renderer (native Metal on Apple Silicon).** Reasons:
- **Editable as text.** Scenes (`.tscn`) and resources (`.tres`) are plain text, scripts are GDScript or C#, and there are no GUID `.meta` files or binary scene data. Claude can author and diff everything directly.
- **Fully scriptable from the CLI.** `godot --headless` runs scripts, imports assets, and runs tests and exports. With a windowed run plus `get_viewport().get_texture().get_image().save_png()`, the screenshot harness can be rebuilt without touching the editor.
- **Good enough quality ceiling for this brief.** It has SDFGI/VoxelGI, volumetric fog, SSAO/SSIL, SSR, glow, auto-exposure, decals, MultiMesh instancing for crowds, and a Jolt physics option (Godot 4.4+). It is MIT-licensed and a small download.
- **Why not Unity.** Unity HDRP has a higher absolute ceiling, but scenes and prefabs are YAML full of GUID cross-references, the editor is GUI-centric, batch mode needs a licence activation, and project churn is heavy. Claude would be much less effective in it.

The first Mac task is to confirm Godot with the owner if they haven't already, install it, and port. See "Porting plan" below.

---

## What was built (three.js prototype, all in this repo)

### Tooling and data (engine-independent, keep these)
- **OSM pipeline**: `tools/osm/fetch.mjs` (Overpass) and `tools/osm/build.mjs` produce `public/packs/chennai/regions/mylapore_marina/` (meta.json and 176 chunk JSONs of 200 m each).
  - Region bbox [13.024, 80.26, 13.052, 80.29], origin 13.0336N 80.2697E. Local metres with x = east, z = south.
  - Contents: 1,337 roads (OSM width and rank), 1,632 junctions, 233 areas (water, beach, park and so on), the coastline, 10 rail ways, 230 POIs and 38 landmarks.
  - 6,410 buildings, each with a footprint (CCW, outward normal = (dz, −dx)), a classified kind (residential 3,652 / commercial 1,950 / agraharam 183 / oldhouse 100 / apartment 225 / institution 152 / informal 129 / temple, church, station, lighthouse and so on), a level count drawn from STYLE_BIBLE distributions, a per-edge **street frontage rank** and the **index of the road it faces** (used for shop addresses).
  - Landmarks: Kapaleeshwarar temple ≈ (10, −27), its tank ≈ (−118, −2), lighthouse (1052, −674), San Thome Basilica (880, 0), Luz Church (−799, −506), Light House MRTS station (775, −1291).
- **Reference research**: `tools/refs/commons.mjs` and `sheet.mjs` pull Wikimedia Commons metadata and thumbnails (local only). Licences are in `data/refs/refs.json`.
- **`docs/STYLE_BIBLE.md`**: numeric rules for light, building heights, chajjas, paint palettes, weathering, shop-front anatomy, roads, vehicle mix, dress, landmarks, kolam, clutter quotas, and the fictional parties TMEK and ATM.
- **City pack data**: `public/packs/chennai/pack.json`, `style.json` (generator numbers) and `names.json` (Tamil + English business-name parts written the way Chennai signboards transliterate, 27 trades with opening hours, upper-floor office boards, flex and paint colour sets).
- **Fonts**: OFL Google Fonts in `public/fonts/` (Baloo Thambi 2, Arima, Catamaran, Kavivanar, Hind Madurai and Noto Sans for Tamil, Telugu, Devanagari, Malayalam and Kannada; Anton and Oswald for English). The script is `tools/fonts/fetch.mjs`.
- **Harness**: `tools/harness/shots.mjs` (Playwright, system Chrome) with shot sets in `shots.json`. Port this idea to Godot.

### Engine code (`src/`; reference for the port)
- `engine/`: WebGPU renderer with auto WebGL2 fallback, a GTAO + bloom + FXAA post chain, input with remapping and gamepad, settings (independent voice, subtitle and UI languages, density sliders, horn intensity and so on), and the stats overlay.
- `crowd/`: procedural low-poly Indian bodies with 6 dress variants (shirt-pants, veshti with border, checked lungi, saree with pallu and jasmine, churidar with dupatta, schoolchild) at 3 LODs. GPU limb animation, head wobble and raised-hand crossing gesture. Nine-tone skin distribution with no colourism. **Spike: 10k people at about 25 fps on UHD 620 with full post.**
- `world/sky.ts`: Chennai day/night keyframes (haze, golden hour, orange light-polluted night sky).
- `world/region.ts`: ground with holes, OSM area polygons, roads as ribbons with junction discs, footpaths and kerbs on tertiary and larger roads, a **stepped granite temple tank** (9 steps down to water), the beach slope strip and an animated sea mesh (surf lines, foam).
- `world/gen/buildings.ts` (runs in a worker): one quad per façade cell (bay × floor) with a cell kind (window, balcony door, shop, glass, vent, door, stilt, trim). Geometry for **chajjas over every opening**, balconies, parapets, AC units, drain pipes, black roof water tanks on stands, mumty headrooms, dish antennas, Mangalore-tile gable roofs on old houses, and full shop fronts (signboard, shutter housing, tube light, plinth step, tin or tarp awning).
- `world/gen/signPainter.ts`: **unique Tamil + English signboards per shop**, painted into a per-chunk atlas. Flex (gradient, emblem, address with the real OSM street name, phone) and hand-painted (border, display fonts, rust and weathering). Verified rendering correctly with Tamil shaping.
- `world/materials.ts`: TSL materials. The façade has procedural windows (MS grilles square and diamond, wooden shutters, aluminium sliders, curtains), shop interiors that open on a schedule, rain streaks, damp band, repaint patches and lit windows at night. Also road (patches, potholes, edge dust, faded dashes, wet puddles), ground, sea, tank water and generic props (tin, tarp, tank, tiles, concrete, granite).
- `world/streamer.ts`: two LOD rings (near 280 m with detail, signs, shadows and colliders; far 1,150 m) using 1–3 Web Workers.
- `physics/physics.ts`: Rapier with a ground and footpath trimesh plus per-chunk building-shell trimeshes.

### Known issues at handoff
1. **Façade composite renders near-black for most buildings** (`materials.ts` facadeMaterial). The debug views `?fdbg=paint|wall|masks|frame|glass|shop|c3|c6|c9|m1|m1b|m2|m3` show the paint, the wall and all masks are correct, but `mix(wallC, winCol/glassCol, mask)` goes dark even where the mask is 0. That points to NaN or Inf in `winCol`/`glassCol` (suspects: `fresnel()` pow, or the division by `ww`). It is moot if the project moves to Godot; otherwise isolate it with `m1` vs `m1b`.
2. Performance on UHD 620 with the city: 10–18 fps (heavy façade shader plus GTAO). Not representative of the Mac.
3. Phase 1 items that remain: player controller, the three camera modes, vehicles (auto, bike, car), and night street lights.

### Screens
`docs/screens/phase0/` (crowd spike), `docs/screens/phase1/` (first city shots, including the night signboards in `bazaar_night.png`), `docs/screens/debug/` (façade bisection).

---

## Porting plan (Mac, Godot 4)
1. Install Godot 4 (stable, macOS universal) and Blender (the Apple Silicon build). Install Node only for the existing data tools.
2. Create `godot/` (or restructure the repo root) with the project. Keep `tools/`, `data/`, `docs/` and the `public/packs/` JSON as the data source.
3. **Importer**: a GDScript `@tool` or headless script that reads the region `meta.json` and chunk JSON and generates meshes with `SurfaceTool`/`ArrayMesh`. Port `buildings.ts` and `region.ts` logic one to one; the cell-quad approach maps directly to a `ShaderMaterial` with custom vertex attributes (`CUSTOM0..3`). Optionally bake chunks to `.res` offline.
4. **Signs**: render the atlas with Godot's `TextServer` (it supports Tamil shaping via HarfBuzz) into an `Image` per chunk, or pre-render PNG atlases with the existing painter in Node or Chrome.
5. **Crowd**: `MultiMeshInstance3D` plus a vertex-shader port of the limb animation. Near tier: rigged MPFB humans from Blender with Mixamo-style retargeted CC0 mocap.
6. **Physics**: Jolt. Use `VehicleBody3D` or a custom raycast vehicle for the three-wheel auto; bikes need balance assist.
7. **Harness**: `godot --path godot -- --shot=<name>` scene that sets the camera and time, waits N frames, saves a PNG and writes a stats JSON. Then continue the BRIEF roadmap from Phase 1.
8. Mac M5 extras now possible: Indic Parler-TTS on MPS (Phase 5), open music models, Blender bakes (VAT, impostors).

---

## Session log
### Session 1 (2026-10-01, ThinkPad)
Phase 0 complete and tagged. Phase 1 partly built (above). STYLE_BIBLE v1 written from 16 Commons references. The local-test note for the crowd: dress mix reads correctly. Missing: faces, hand detail and gait variety (acceptable for mid and far tiers only).

### Phase 1 acceptance (Godot) — 2026-10-01
- Shots: `docs/screens/phase1/` (overview, mada_street, kutchery_road, temple_tank, marina, bazaar_night, player_scene, drive_auto); stats in `report.json`.
- Drive test: autopilot auto, 90 s sim, **545 m across 36 streamed chunks, 0 flipped frames**, chunk generation 40–90 ms on a worker thread, typical main-thread upload ≤ 10 ms. One upload spike of 2.4 s on lavapipe (software Vulkan) — profile on the Mac; suspect first-use pipeline compilation of a new material, fix with a warm-up pass at load if it reproduces.
- Local test (would a Chennai native notice anything wrong?): yes — no people or traffic yet (Phase 3), parked bikes are boxy placeholders, ground between buildings is too open in places, shop interiors are generic. Recorded as Phase 2/3 work.
- Performance numbers from the cloud harness are software-rendered (~1 fps) and not meaningful; measure fps on the M5.

### Session 2 (2026-10-01, cloud workspace + Mac link)
- Installed Godot 4.7.2 (Linux build) with Mesa lavapipe + Xvfb for headless screenshots. Fonts re-fetched as full TTFs. Procedural texture set generated.
- Ported Phase 1 to Godot (see Current state). Fixed: camera-rig spring arm override, ground vertex blow-up near tanks, harness idle detection.
- Drive test (auto, 30 s sim): 169 m, 19 chunks streamed, no flips. Performance numbers in the cloud are software-rendered and not meaningful; measure on the Mac.
- Local test notes: streets look empty — OSM building coverage in Mylapore is partial; infill is the top priority.
