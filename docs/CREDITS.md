# Credits

## Data
- **OpenStreetMap**: map data © OpenStreetMap contributors, licensed under the Open Database License (ODbL) 1.0. https://www.openstreetmap.org/copyright. Fetched via the Overpass API (overpass-api.de). Used for roads, buildings, land use, water, coastline, railways and POIs in `public/packs/*/regions/`.

## Reference imagery (not shipped; used only for measurement)
Wikimedia Commons; per-image licence and author in `data/refs/refs.json`. The images measured for STYLE_BIBLE v1 (Commons page IDs): 120606260, 120606431, 120608107, 120606249 (CC BY-SA 4.0, "Street views in Chennai 2K22TNKAN"); 23467177, 23467178, 23467735 (CC BY 2.0); 37505740, 37505733 (CC BY-SA 3.0, panoramio); 33160727 (CC BY 2.0); 47272630 (CC BY-SA 2.0); 1952452 (CC BY-SA 2.5); 55333571 (CC BY-SA 3.0); 15681380 (CC BY-SA 3.0); 19778423 (CC BY-SA 2.0); 2423496 (CC BY-SA 2.5).

## Engine and runtime
- **Godot Engine 4.7.2** (MIT): https://godotengine.org — engine, Jolt physics module (MIT).
- **Mesa / lavapipe** (MIT) and **Xvfb** (MIT/X11): used only by the headless screenshot harness in the build workspace.

## Fonts (SIL Open Font License 1.1; licence texts in `godot/fonts/OFL_*.txt`)
From https://github.com/google/fonts: Baloo Thambi 2, Arima, Catamaran, Noto Sans Tamil, Kavivanar, Hind Madurai, Mukta Malar, Meera Inimai, Anton, Oswald, Noto Sans, Noto Serif, Noto Sans Telugu, Noto Sans Devanagari, Noto Sans Malayalam, Noto Sans Kannada.

## Textures
- All surface textures in `godot/textures/` are generated procedurally by `tools/textures/gen.py` (this project; CC0).

## Tools
- numpy (BSD-3), Pillow (MIT-CMU), SciPy (BSD-3) for offline texture generation.

## Libraries (three.js prototype, reference only)
- three.js (MIT): https://github.com/mrdoob/three.js
- Rapier / @dimforge/rapier3d-compat (Apache-2.0): https://rapier.rs
- Vite (MIT), TypeScript (Apache-2.0), Playwright (Apache-2.0)
