# Sprint 06 — QC Expansion (Color/HDR/Metadata)

## Goal
Expand deterministic QC coverage beyond structural checks into content + color/metadata checks aligned with `Docs/CONCEPT_QUALITY_GOVERNANCE.md`, plus creator-critical audio/caption checks.

Legacy references:
- CoreML/Vision determinism stance: `Docs/research_notes/legacy_autopsy_coreml_vision.md`
- Export/perf stance: `Docs/research_notes/legacy_autopsy_optimizations_apple_silicon.md`

## Acceptance criteria
- Integrate deterministic *content* QC into the deliverables path (not only ad-hoc tests):
  - Color stats (luma histogram-derived metrics + coarse RGB) on deterministic keyframes.
  - Temporal variety check to catch “stuck source” regressions.
- Add at least 1 deterministic *metadata* QC check (no network, fast):
  - Codec string, nominal fps, and container/track color metadata when available.
  - Bit-depth/pixel format expectations where APIs permit (graceful “unknown” when not).
- Add deliverable-bundle QC for sidecars:
  - Validate required sidecars exist on disk when requested/required.
- QC results include measured metrics (not just pass/fail) and are persisted (manifest).
- E2E: export deliverable bundle and pass the expanded QC.

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
- `Sources/MetaVisExport/Deliverables/DeliverableManifest.swift` (embed expanded QC results)
- `Sources/MetaVisSession/ProjectSession.swift` (wire QC expansion into deliverable export)

## New/extended building blocks
- Already present:
  - `Sources/MetaVisPerception/Services/VideoAnalyzer.swift` (statistical frame metrics)
  - `Sources/MetaVisPerception/Models/VideoAnalysis.swift`
  - `Sources/MetaVisQC/VideoContentQC.swift` (temporal variety + color stats helpers)

## New code to add
- Optional: `Sources/MetaVisQC/Checks/*` for modular checks (only if it reduces complexity).

Suggested checks (deterministic + cheap):
- Use existing `VideoContentQC.validateColorStats(...)` as the initial implementation.
- Consider extracting “checks” only after wiring is stable.

Suggested checks (metadata-driven, non-network):
- `ExportBitDepthCheck`: verify expected pixel format / bit depth where APIs permit (10-bit where requested).
- `ColorMetadataCheck`: validate primaries/transfer/matrix and HDR flags are present/consistent when expected.
- `SidecarPresenceCheck`: validate deliverable bundle includes expected sidecar files.

## Existing tests to update
- Prefer adding new tests under existing targets:
  - `Tests/MetaVisExportTests/*` for export+QC+manifest E2E
  - `Tests/MetaVisPerceptionTests/*` for deterministic analyzer metrics

## Deterministic generated-data strategy
- Use procedural SMPTE/macbeth generators.
- Export short clips; sample specific timestamps deterministically.

## Test strategy (no mocks)
- E2E: export deliverable bundle → QC with the expanded checks enabled → manifest embeds results.
- Avoid pixel-perfect comparisons; prefer downsampled metrics and stable hashes.

## Deliverables
- Wire existing content QC into the deliverable pipeline and persist results in `deliverable.json`
- Add at least 1 new metadata QC check emitting numeric/string metrics
- Add deliverable sidecar QC (presence/requirements)
- One E2E deliverable test that exercises expanded QC + manifest embedding
- One unit test that locks in deterministic `VideoAnalyzer` metrics on a synthetic pixel buffer

## Current state (as of 2025-12-13)
- Content QC helpers already exist (`VideoContentQC.assertTemporalVariety`, `VideoContentQC.validateColorStats`) and are exercised by `Tests/MetaVisExportTests/MultiClipExportTest.swift`.
- Deliverables embed structural+audio QC plus expanded QC metrics in `deliverable.json` (manifest schema v4):
  - Metadata QC (codec FourCC + track color metadata when available)
  - Content QC fingerprints + adjacent distances (informational; policy-gating can be reintroduced later)
  - Sidecar QC (requested vs written + byte sizes)

## Sprint focus
1) Move content QC from “test-only” into the deliverables QC pipeline.
2) Add metadata QC and sidecar QC.
3) Evolve manifest QC report schema to store these metrics (backward compatible).
