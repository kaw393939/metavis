# Project Plan — Keith Talk Editing Demo

## Goal
Demonstrate core “video editing” operations (trim, cut, move, b-roll overlay, audio normalization, export) on a real talking-head clip.

## Inputs
- `assets/keith_talk.mov` (primary)
- `assets/test_bg.mov` (optional b-roll/background)
- `assets/old_world_map.jpg` (optional overlay)

## Deliverables (outputs)
- A short 30–60s highlight cut.
- A second export demonstrating a simple edit difference (e.g., moved cut point, added b-roll, or title card).

## Demo Script (MVP)
1. Ingest `keith_talk.mov` into a timeline.
2. Make 3 cuts (remove pauses / stumbles).
3. Add `test_bg.mov` as a cutaway for ~3 seconds.
4. Add `old_world_map.jpg` as a 1–2s overlay/title card.
5. Export a review proxy and a master.

## Constraints
- Skip any automated analysis of the long clip unless explicitly requested.
- Keep renders deterministic/reproducible (fixed frame rate, fixed quality preset).

## Later (optional)
- If we choose to analyze, use `eai transcribe_video` to create searchable chapter markers, then convert into deterministic edit commands.
