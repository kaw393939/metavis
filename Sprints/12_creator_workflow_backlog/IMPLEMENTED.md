# Implemented Features

## Status: In Progress (Foundations + Partial Wiring)

## Accomplishments
- **Vision**: Defined "Clean Water" north star.
- **Strategy**: Local-first, ACEScg, iPhone-to-Mac.
- **Backlog**: Themes for future execution.

## Reality Check (Existing Foundation)
- **EXR ingest infrastructure exists** (ffmpeg-based decode path + tests), but the larger ACEScg/EXR-as-truth workflow described in Sprint 12 is not fully productized.
- **Science ingest foundation exists (FITS)**: a FITS reader + asset model + registry are now in Sources (not yet wired into the render/export workflow).
- **Simulation can ingest FITS stills**: `ClipReader` can now decode `.fits/.fit` into RGBA16F Metal textures for preview/render paths (true scientific compositing/metadata workflows still pending).
- **FITS → timeline → export is now wired end-to-end**: `MetaVisLab fits-timeline` can build a deterministic timeline from `Tests/Assets/fits/` and export a playable movie.
- **False-color + inspection outputs exist for FITS**: Turbo false-color (`com.metavis.fx.false_color.turbo`) supports tunable `exposure` and `gamma`, and optional EXR extraction can write per-clip midpoint frames.
- **Caption sidecar writing foundation exists**: cue-based SRT/VTT rendering is available, and deliverable export will best-effort copy existing sibling sidecars (or convert between `.vtt` and `.srt`) when the timeline clearly references a single local source asset.
- **Timing foundation exists**: ingest can probe video PTS deltas for a VFR-likelihood signal (normalization + robust A/V sync policy remains backlog).
- **VFR normalization policy exists (decision layer)**: a deterministic `VideoTimingNormalization` suggests a CFR timebase (snaps to common FPS) and recommends frame-step; full resampling and edit-aware A/V sync are still backlog.
