# GTIndian — project memory

An open-world crime game set in an authentic South India (Chennai first). It runs in the browser. The full brief is in `BRIEF.md`; the roadmap is in `docs/PLAN.md`; the session log and next steps are in `docs/PROGRESS.md`. **Read `docs/PROGRESS.md` first every session.**

Repo: https://github.com/Aweswomedude1234/GTChennai (private). **Status: moving to a MacBook Air M5 (24 GB), and from the browser stack to a native engine (recommendation: Godot 4; see PROGRESS.md). The 20-second web load target is dropped.** The three.js code below is the prototype and reference for the port.

## Stack
TypeScript + Vite + pnpm · three.js r186 `three/webgpu` (WebGPURenderer, TSL node materials, auto WebGL2 fallback) · Rapier (`@dimforge/rapier3d-compat`) · Playwright harness.

## Commands
- `pnpm dev`: dev server on http://localhost:5199 (`?mode=spike` runs the crowd spike).
- `pnpm typecheck`
- `node tools/osm/fetch.mjs` then `node tools/osm/build.mjs`: Overpass → `public/packs/<city>/regions/<id>/` (regions are in `data/regions.json`).
- `node tools/harness/shots.mjs <set> --channel=chrome`: screenshots and stats to `docs/screens/<set>/` (sets are in `tools/harness/shots.json`). Use `--channel=chrome`: Playwright's bundled Chromium lacks dxil.dll, so it has no WebGPU. Add `--q=key=val` for URL overrides.
- `node tools/refs/commons.mjs`, `tools/refs/sheet.mjs`: reference images (local only, gitignored).

## URL params (dev and harness)
`backend=webgl` · `post=0` · `quality=low|medium|high|ultra` · `hour=17.5` · `cam=x,y,z,tx,ty,tz` · `spawn=x,z` · `mode=spike` · any `Settings` key.

## Layout
- `src/engine/`: renderer, input, settings, stats, rng
- `src/world/`: sky/time, region loader, chunk streamer and worker, roads, buildings, props, signs, textures
- `src/crowd/`: procedural humans (`humanMesh.ts`), dress and skin appearance, GPU crowd renderer
- `src/physics/`, `src/player/`, `src/vehicles/`, `src/game/`, `src/ui/`, `src/audio/`
- `public/packs/<city>/`: city data packs (pack.json, style.json, regions, names, dialogue)
- `data/`: source data (regions.json, OSM raw (gitignored), characters, missions, refs)
- `tools/`: offline pipelines (osm, harness, refs, blender, tts, audio)
- `docs/`: PLAN, PROGRESS, DECISIONS, BLOCKERS, PLACEHOLDERS, CREDITS, STYLE_BIBLE, missions/, screens/

## Conventions
- World units are metres. x = east, z = south, y = up. The region origin is in `data/regions.json`. Person and vehicle `heading` h faces (sin h, cos h) in xz.
- Three applies `positionNode` **after** instancing: animate with `positionGeometry` and add a rotated delta (see crowdRenderer.ts).
- WebGPU allows at most **8 vertex buffers**, so pack per-instance data into one `InstancedInterleavedBuffer`.
- Everything is deterministic from seeds (OSM way id → building seed).
- No real brands, parties or politicians. The fictional parties are TMEK (Aadhavan) and ATM (Nagaraj); see STYLE_BIBLE §10.
- Dev machine: MacBook Air M5, 24 GB (from 2026-10). The old ThinkPad (UHD 620) numbers in the docs are integrated-GPU numbers.
- Commit as Aweswomedude1234, with the Co-Authored-By Claude trailer.
