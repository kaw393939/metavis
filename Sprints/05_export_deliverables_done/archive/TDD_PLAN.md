# Sprint 05 — TDD Plan (Export Deliverables)

## Tests (write first)

### 1) `DeliverableE2ETests.test_export_deliverable_bundle_contains_mov_and_manifest()`
- Location: `Tests/MetaVisExportTests/DeliverableE2ETests.swift`
- Steps:
  - Build deterministic timeline.
  - Export deliverable bundle to temp directory.
  - Assert `video.mov` exists.
  - Assert `deliverable.json` exists and decodes.

### 2) `DeliverableE2ETests.test_manifest_contains_qc_results()`
- Run deterministic `VideoQC` on `video.mov`.
- Assert manifest QC results match expectations (pass, with measured values recorded).

### 3) `DeliverableE2ETests.test_export_uses_gpu_pixelbuffer_path_by_default()`
- Guardrail test: assert the default export path is compatible with GPU→`CVPixelBuffer` conversion (i.e., does not rely on `texture.getBytes`).
- Implementation detail is flexible; the test can be an instrumentation counter or a gated debug flag.

### Optional follow-up (if deliverables include captions in v1)
- `DeliverableE2ETests.test_deliverable_can_write_caption_sidecars()` asserts `.srt`/`.vtt` exist when requested by policy/output type.

## Production steps
1. Add deliverable schema + writer.
2. Add export entrypoint in session/export.
3. Ensure atomic write + cleanup on failure.

## Definition of done
- E2E tests pass with real exports and real QC.

Reference for later perf work: `Docs/research_notes/legacy_autopsy_optimizations_apple_silicon.md`
