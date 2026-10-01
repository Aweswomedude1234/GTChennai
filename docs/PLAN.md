# GTIndian roadmap (status per item)

Legend: [x] done · [~] partial · [ ] todo

## Phase 0: Foundation
- [x] Repo, Vite/TS/pnpm, three r186 WebGPU and Rapier installed
- [x] CLAUDE.md, BRIEF.md, docs skeleton
- [x] Playwright harness with screenshots and stats JSON (`tools/harness`)
- [x] Stats overlay (fps, draws, tris, heap, NPC/vehicle counts)
- [x] OSM pipeline (Overpass fetch to region pack, Mylapore & Marina)
- [x] Reference research (Commons) and STYLE_BIBLE with numeric rules
- [x] Spike: WebGPU + Rapier + 10k instanced animated people (25–30 fps on UHD 620 with full post)

## Engine switch (2026-10): port to Godot 4 on Mac (see PROGRESS.md "Porting plan"). Phase 1+ items now refer to the Godot build; [~] marks the three.js prototype.

## Phase 1: Core engine
- [x] City pack format (pack.json, style.json, names.json) and region loader (Godot)
- [x] Chunk streamer (WorkerThreadPool building generator, near/far rings, upload budget)
- [x] Ground, roads (OSM widths, junction patches, kerbs, markings), tank, sea and beach
- [x] Physics world (Jolt): ground/beach/tank/kerb colliders, per-chunk building shells
- [x] Player on foot (CharacterBody3D): walk, jog, sprint, jump, step-up
- [x] Cameras: third-person, first-person, top-down; settings switch (C)
- [x] Day/night integrated (time controls [ ])
- [x] Vehicles: raycast physics for auto (3-wheel, tippy), bike (2-wheel, lean controller), car; enter and exit
- [x] Acceptance: walk and drive across streamed chunks (harness drive test: 545 m, 36 chunks; one lavapipe upload spike to re-check on the Mac)

## Phase 2: Chennai slice (Mylapore + Marina)
- [~] OSM plot infill (6.4k → 22.8k buildings), horizon LOD
- [~] Procedural buildings: residential, commercial, agraharam, old house, apartment, institution, informal; chajjas, grilles, balconies, AC units, roof tanks, parapets, weathering shader
- [ ] Shop fronts with unique Tamil + English signboards (sign atlas), shutters, awnings, tube lights, stock
- [~] Props: poles, cables, street lights, posters, parked two-wheelers, crates, carts, drains, speed breakers, potholes, trees, compound walls, kolams
- [~] Kapaleeshwarar temple: gopurams, vimana, mandapams, kaavi walls, tank with steps (neerazhi mandapam todo)
- [~] Marina: sand, lighthouse, vendor carts, fishing boats, promenade lamps, sea shader
- [ ] Churches (San Thome, Luz), MRTS elevated line
- [ ] Night lighting: street lights, shop tubes, window glow
- [ ] Density audit tool (BRIEF §15 per-100 m quotas); screenshot review against refs

## Phase 3: Life
- [~] Realistic humans (MPFB + CMU mocap), near skeletal tier + VAT mid tier
- [~] Pedestrian sim on footpaths and road edges, crossing with a raised hand, idle behaviours, schedules
- [ ] Traffic sim on the OSM graph: gap-seeking, two-wheeler filtering, horns, signals, jams
- [ ] Vehicle fleet models (35+) with liveries and wear
- [ ] Animals: dogs, cows, crows, goats
- [ ] Vendors and stalls with calls
- [ ] Ambience audio layers, spatial audio, radio (2+ stations)
- [ ] Weather: rain, wet roads, waterlogging, monsoon, power cuts
- [ ] Acceptance: 1,500+ visible people and jams at target fps

## Phase 4: Crime and police
- [ ] Melee and firearms, hit reactions and ragdolls, cover
- [ ] Heat levels 1–4 with TN police AI and roadblocks
- [ ] Bribe negotiation system
- [ ] Respect rules: no combat in worship spaces; animals and children are excluded

## Phase 5: Voice and language
- [ ] i18n system: voice, subtitle and UI languages independent (ta, te, hi, ml, kn, en)
- [ ] Character voice registry (data/characters/*.json)
- [ ] TTS pipeline (Indic Parler-TTS) with Opus encoding; barks; lip sync

## Phase 6: Act 1
- [ ] Missions 1–11, phone and messaging, safehouse, economy

## Phase 7: Village (Act 2)
## Phase 8: Full Chennai
## Phase 9: Act 3 and politics
## Phase 10: Second city pack
