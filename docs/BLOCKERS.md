# Blockers & workarounds

| Date | Blocker | Workaround | Owner action |
|---|---|---|---|
| 2026-10-01 | Indian Driving Dataset (IDD) needs registration | Vehicle mix from published Chennai traffic studies and Commons photos (STYLE_BIBLE §5, marked est.) | Optional: download IDD to `data/idd/` |
| 2026-10-01 | No discrete GPU on the dev machine (UHD 620) | Measure on integrated graphics and keep generous LOD and density sliders | Test on a discrete GPU later |
| 2026-10-01 | Playwright Chromium has no WebGPU (dxil.dll) | Use system Chrome in the harness | — |
| 2026-10-01 | three.js façade composite renders near-black (suspected NaN in window/glass colour) | Debug views `?fdbg=` added; superseded if the project moves to Godot | — |
