# Decisions log

| Date | Decision | Reason | Alternatives |
|---|---|---|---|
| 2026-10-01 | three.js r186 `three/webgpu` (not Babylon) | Native TSL node materials, WebGPU and WebGL2 from one codebase, instancing, a built-in post chain (GTAO, bloom, FXAA) and clustered lighting addon. The spike worked on the first day. | Babylon.js (heavier, fewer TSL-like shader tools) |
| 2026-10-01 | City terrain is flat (y=0) with a procedural beach slope; DEM deferred to the village and highway regions | Chennai's slice is 2–8 m above sea level, and SRTM's ±3–5 m noise (buildings and trees) is larger than the real relief, so it would make roads bumpy and wrong | Copernicus DEM everywhere |
| 2026-10-01 | Harness uses system Chrome (`--channel=chrome`) | Playwright Chromium's Dawn fails to load dxil.dll on this machine, so it falls back to WebGL2 | SwiftShader (very slow) |
| 2026-10-01 | Post chain: single-sample scene pass, then GTAO, bloom and FXAA | MSAA depth textures cannot be gathered by GTAO under WebGPU | MSAA without AO |
| 2026-10-01 | Crowd mid and far tiers are procedural low-poly bodies animated in the vertex shader (limb pivots, head wobble, raised hand), with 3 LODs (~900 / ~350 / ~60 tris) | 10k people in about 160 draw calls; an equivalent of VAT without an offline bake. The near tier will get Blender-built rigged humans. | VAT bake from Blender (Phase 3 upgrade path) |
| 2026-10-01 | Performance budgets are measured on the Intel UHD 620 dev laptop | That's the hardware available. The integrated-graphics target is 30 fps on Low; we estimate a mid-range discrete GPU is 6–8× faster. | — |
| 2026-10-01 | Fictional city bus operator "MNT" (Maanagara Naveena Transport) with MTC-like blue livery | The brief requires fictional brands while keeping a realistic look | Use MTC directly |
| 2026-10-01 | Fictional parties TMEK (lighthouse, maroon/teal) and ATM (palmyra, sky blue/white/yellow) | Checked against the TN party flags and symbols listed in STYLE_BIBLE §10 | — |
| 2026-10-01 | Chunk size 200 m; buildings bucketed by centroid; roads, areas and the coast are global in meta.json | A 3.2 × 3.1 km region has 176 chunks with about 36 buildings each, and roads are only 0.5 MB in total | Per-chunk road clipping |
