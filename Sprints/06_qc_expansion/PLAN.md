# Sprint 06 — QC Expansion (Color/HDR/Metadata)

## Goal
Expand deterministic QC coverage beyond structural checks into content + color/metadata checks aligned with `CONCEPT_QUALITY_GOVERNANCE.md`, plus creator-critical audio/caption checks.

Legacy references:
- CoreML/Vision determinism stance: `Docs/research_notes/legacy_autopsy_coreml_vision.md`
- Export/perf stance: `Docs/research_notes/legacy_autopsy_optimizations_apple_silicon.md`

## Acceptance criteria
- Add at least 2 new deterministic QC checks that run fast and do not require network:
  - Example: validate a frame-average luminance range for SMPTE bars.
  - Example: validate codec/bit-depth metadata expectations where available.
  - Example: validate audio is present and within a coarse loudness/peak range (tolerant).
  - Example: validate caption sidecars exist when a deliverable requires them.
- QC results include measured metrics (not just pass/fail).
- E2E test exports a known pattern and passes the new QC checks.

Determinism note:
- Deterministic render/QC checks may use strict hashes on downsampled frames.
- ML/perception-derived checks must use tolerant numeric metrics and record model/config metadata.

## Perception alignment (Phase 3 spec)
This sprint’s QC expansion should reuse the same deterministic, downsampled frame metrics required by the Perception “eyes” spec (color stats first).

Minimum shared outputs:
- Luma histogram (256 bins)
- Average color (RGB)
- Optional: dominant colors (coarse quantized)

These metrics should be computed on CPU/downscaled proxies to keep runs fast + deterministic.

## Existing code likely touched
- `Sources/MetaVisQC/VideoQC.swift`
- `Sources/MetaVisQC/VideoContentQC.swift`
- `Sources/MetaVisCore/ImageComparator.swift` (if used for content comparison)

## New/extended building blocks
- `Sources/MetaVisPerception/Services/VideoAnalyzer.swift` (statistical frame metrics)
- `Sources/MetaVisPerception/Models/VideoAnalysis.swift`

## New code to add
- `Sources/MetaVisQC/Checks/*` (optional folder) for modular checks.

Suggested checks (deterministic + cheap):
- `LumaHistogramCheck`: verify histogram shape/peak for known test patterns (SMPTE bars, ramps)
- `AverageColorCheck`: verify average RGB falls in expected range for known patterns

Suggested checks (metadata-driven, non-network):
- `ExportBitDepthCheck`: verify expected pixel format / bit depth where APIs permit (10-bit where requested).
- `ColorMetadataCheck`: validate primaries/transfer/matrix and HDR flags are present/consistent when expected.

## Existing tests to update
- `MetaVisQC` tests if any are asserting exact error codes/messages.

## Deterministic generated-data strategy
- Use procedural SMPTE/macbeth generators.
- Export short clips; sample specific timestamps deterministically.

## Test strategy (no mocks)
- E2E: export → QC with the new checks enabled.
- Avoid pixel-perfect comparisons; prefer downsampled metrics and stable hashes.

## Deliverables
- At least 2 new QC checks emitting numeric metrics
- One E2E export test that exercises the new checks
- One unit test that locks in deterministic `VideoAnalyzer` metrics on a synthetic pixel buffer
