# Project Plan — Procedural Validation Demo

## Goal
Demonstrate deterministic rendering/export without depending on local media files.

## Inputs
- Procedural video: `ligm://video/smpte_bars`, `ligm://video/zone_plate`, `ligm://video/macbeth`, `ligm://video/frame_counter`
- Procedural audio: `ligm://audio/sine`, `ligm://audio/sweep`, `ligm://audio/impulse`

## Deliverables (outputs)
- A 2s smoke export.
- A 10–20s “stress-ish” multi-layer export.

## Demo Script (MVP)
1. Start from `StandardRecipes.SmokeTest2s`.
2. Export proxy + master.
3. Switch to a layered timeline (multi-track video + audio) and export.

## Constraints
- No file dependencies; should work on a clean machine.
- Deterministic output (suitable for golden/probe comparisons).
