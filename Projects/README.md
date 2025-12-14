# Demo Projects

This folder contains curated, reproducible demo projects for MetaVis.

Design goals:
- Keep the canonical media library in `assets/`.
- Each project has its own `assets/` folder containing symlinks into `assets/`.
- Each project includes a `PLAN.md` with a crisp demo script + expected outputs.

## Projects
- `keith_talk_editing_demo/` — talking-head editing demo using `keith_talk.mov` (no automatic content analysis).
- `broll_montage_demo/` — fast montage demo from short B-roll clips + stills.
- `procedural_validation_demo/` — procedural-only timeline (no file assets) for deterministic export demos.
- `audio_cleanwater_demo/` — audio effect demo (Dialog Cleanwater) with simple video background.

## Notes
- The `test_outputs/` folder contains generated artifacts from tests; it’s not used as source media.
