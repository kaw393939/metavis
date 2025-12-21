# Awaiting Implementation

## Gaps & Missing Features
- **End-to-end deliverables**: Several Sprint 12 foundations are now wired end-to-end (notably FITS stills → timeline → export), but the broader creator workflow items remain incomplete.
- **Foundational pieces already present** (partial, not the full workflow):
	- EXR decode infrastructure exists (used for ingest/tests/tooling).
	- FITS ingest foundation exists (reader + asset model + registry).
	- Caption sidecar foundation exists (cue-based SRT/VTT rendering + best-effort copy of existing sibling `.vtt/.srt` sidecars during export when the timeline has a single local source).
	- Ingest captures `nominalFPS` metadata and can probe PTS deltas for VFR-likelihood.

## High-priority backlog gaps (still missing)
- **Science data ingest (FITS/JWST)**: FITS stills can now be rendered/exported end-to-end, but there is still no explicit `ScientificRaster` pipeline (multi-band compositing + metadata contract) promoted as a first-class workflow.
- **VFR normalization + sync**: VFR probing exists and a normalization *decision* policy exists, but there is still no explicit normalize-to-timebase resampling pipeline or robust edit-aware A/V sync strategy.
- **ACEScg working-space contract**: no explicit “ACEScg at the door” conversion + deterministic SDR preview contract enforced across ingest→render→export.
- **Dialog + captions**: no STT, diarization, timed cue generation, edit-aware cue retiming, or caption embedding/burn-in pipeline.
- **Seamless iPhone→Mac transfer**: pairing/transport/resume/integrity workflow is planning-only.

## Deferred follow-up (Sprint 12): FITS → video + Gemini feedback loop
- **Status**: Implemented for local deterministic export + regression coverage; Gemini feedback loop remains optional.
- **Goal**: Use the existing FITS ingest + simulation decode to render a short video from the JWST FITS sequence in `Tests/Assets/fits/`, then (optionally) run Gemini QA feedback iteratively until the FITS data path is verified as correct.
- **Why**: This FITS dataset is known-good and was previously rendered successfully in the earlier projects; we should treat it as the canonical regression fixture for scientific ingest.
- **Input dataset**: `Tests/Assets/fits/`
	- `hlsp_jwst-ero_jwst_miri_carina_f770w_v1_i2d.fits`
	- `hlsp_jwst-ero_jwst_miri_carina_f1130w_v1_i2d.fits`
	- `hlsp_jwst-ero_jwst_miri_carina_f1280w_v1_i2d.fits`
	- `hlsp_jwst-ero_jwst_miri_carina_f1800w_v1_i2d.fits`

- **Implementation sketch (now)**:
	- `MetaVisLab fits-timeline` builds a deterministic timeline from a FITS folder (one still clip per FITS, sorted) and exports a `.mov`.
	- Optional false-color: Turbo colormap with tunable `exposure` and `gamma`.
	- Optional EXR extraction: writes per-clip midpoint frames as `.exr` for inspection.

- **Acceptance criteria**:
	- Produces a playable `.mov` deliverable from `Tests/Assets/fits/` using the current FITS pipeline (no manual conversion steps).
	- Export is deterministic in structure (stable clip ordering + stable runtime behavior) and passes local QC (probeable, not-black samples).
	- Add at least one XCTest-style regression that asserts stable properties of the export (e.g., non-black frames, temporal variety across the 4 FITS clips).
	- Optional: Gemini QA feedback reports no obvious ingest/normalization errors (e.g., black frames, wrong orientation).

## Recommendations
- Proceed with Sprint 13+ to implement remaining creator-workflow gaps (ScientificRaster compositing, ACEScg contract, VFR normalization/sync, captions).
