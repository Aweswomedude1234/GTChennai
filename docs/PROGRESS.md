# Progress log

## Session 1 (2026-10-01)
**Phase 0 complete.**
- Project scaffolded at `C:\Users\nithi\Projects\gtindian` with git.
- OSM: Mylapore & Marina bbox [13.024, 80.26, 13.052, 80.29] → 1,337 roads, 1,632 junctions, 6,410 buildings (classified: 3,652 residential, 1,950 commercial, 183 agraharam, 225 apartment, …), 233 areas, coastline, 10 rail ways, 38 landmarks; 176 chunks of 200 m.
- Spike (`?mode=spike`): 10k people across 6 dress variants × 3 LODs, GPU limb animation, Rapier boxes. Perf on UHD 620 / Chrome WebGPU at 1600×900: **~25 fps with GTAO+bloom+FXAA**, ~30 fps without post; 160 draws; 0.75M tris visible. Screens: `docs/screens/phase0/`.
- STYLE_BIBLE v1 written from 16 Commons references.

### Local test (phase 0 spike)
Dress mix reads correctly (sarees with pallu, veshti with border, checked lungis, churidar with dupatta). Missing: faces, hands detail and walking variety; this is acceptable for mid and far tiers only.

### Next
Phase 1: pack format, region loader, chunk streamer and worker, roads, player, cameras, vehicles.
