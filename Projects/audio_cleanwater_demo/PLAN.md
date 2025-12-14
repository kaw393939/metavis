# Project Plan — Audio Cleanwater Demo

## Goal
Demonstrate audio processing + QC guardrails:
- baseline tone
- tone with `audio.dialogCleanwater.v1`
- show deterministic gain increase

## Inputs
- Procedural audio: `ligm://audio/sine?freq=1000` (or a dialog-like source later)
- Optional background: `assets/grey_void.mp4`

## Deliverables (outputs)
- Export A (no cleanwater)
- Export B (cleanwater applied)
- A QC report showing audio track present and non-silent

## Demo Script (MVP)
1. Build a 2s timeline with a background video and a 1kHz tone.
2. Export without the effect.
3. Apply `audio.dialogCleanwater.v1` to the audio clip.
4. Export again.
5. Run audio probe/QC to show peak/RMS increase.
