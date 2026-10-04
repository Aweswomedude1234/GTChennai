# Placeholders (must all be replaced before "done")

| Item | Where | Replace with | Status |
|---|---|---|---|
| Player and humans use the procedural segmented body (`ProcHuman`) | godot/scripts/people/proc_human.gd | Blender/MPFB rigged humans with real faces, clothing meshes and mocap | open |
| Auto, bike and car meshes are procedural prisms (`VehicleDefs`) | godot/scripts/vehicles/vehicle_defs.gd | Blender-modelled vehicles (35+ models, liveries, wear) | open |
| Shop signs only (no stock, owners, posters) | building_gen.gd / street_detail.gd | Full shop fronts per BRIEF §15 | open |
- **Audio (2026-10-04):** every sound in `godot/audio/` is synthesised by `tools/audio/gen.py` (horns, engine loops, traffic/crowd ambience beds, temple bell, crow). Replace with field recordings of Chennai streets (same file names) when available; vendor calls and voice barks await the TTS pipeline (Phase 5).
