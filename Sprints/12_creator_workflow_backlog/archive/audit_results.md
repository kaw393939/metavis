# Sprint 12 Audit: Creator Workflow Backlog

## Status: In Progress (Foundations + Partial Wiring)

## Accomplishments
- **Vision Definition**: Established the "Clean Water" north star for solo creators using iPhone and Mac.
- **Product Stance**: Formalized the "Local-first, Mac-first, Privacy-first" philosophy.
- **Format Contracts**: Defined ACEScg as the internal "truth" format and established a quality ladder (EXR > iPhone HDR > Deliverables).
- **Backlog Themes**: Categorized future work into Science Data, iPhone Transfer, Director View, Dialog Cleanup, Captions, and Output Types.
- **Science ingest foundation (FITS)**: FITS reader + asset registry exist; simulation can decode `.fits/.fit` stills for preview/render.
- **End-to-end wiring (FITS → timeline → export)**: `MetaVisLab fits-timeline` can build a deterministic timeline from a FITS folder and export a playable movie.
- **Caption sidecar foundations**: Cue-based `.srt/.vtt` writing exists, with best-effort sidecar copy/convert for simple single-source timelines.
- **Timing foundations**: Video timing probing (PTS delta heuristics) exists, plus a deterministic normalization *decision* layer.

## Gaps & Missing Features
- **Creator workflow remains incomplete**: The broader end-to-end “creator workflow” described by Sprint 12 is not fully productized.
- **VFR normalization + sync**: Probing and a normalization decision exist, but a full resampling pipeline and edit-aware A/V sync strategy remain backlog.
- **Scientific raster pipeline**: FITS stills can be rendered/exported, but there is still no first-class multi-band `ScientificRaster` compositing + metadata contract.
- **ACEScg enforcement**: No explicit “ACEScg at the door” conversion + deterministic SDR preview contract enforced across ingest→render→export.
- **Dialog + captions**: No STT/diarization/timed cue generation/edit-aware cue retiming pipeline.
- **Seamless iPhone→Mac transfer**: Pairing/transport/resume/integrity workflow remains planning-only.

## Performance Optimizations
- **M-Series Focus**: The plan explicitly targets Apple Silicon optimizations, which will be the focus of future implementation sprints.

## Low Hanging Fruit
- Create a `ScientificRaster` protocol in `MetaVisCore` to begin formalizing the science data path.
- Implement a basic `VFRDetector` in `MetaVisQC` to identify problematic iPhone footage early.
