# Sprint 20 — TDD Plan (ACEScg + Deterministic SDR Preview)

## Tests (write first)

### 1) `ACEScgWorkingSpaceContractTests.test_compiler_inserts_idt_and_odt_for_rec709_sources()`
- Build a single-clip timeline using `ligm://fx_macbeth`.
- Compile a frame.
- Assert graph contains:
  - at least one `idt_rec709_to_acescg` node
  - exactly one `odt_acescg_to_rec709` node
  - root shader is `odt_acescg_to_rec709`

### 2) `ACEScgWorkingSpaceContractTests.test_exr_sources_use_linear_idt()`
- Build a single-clip timeline using `assets/exr/AllHalfValues.exr`.
- Compile a frame.
- Assert graph contains `idt_linear_rec709_to_acescg`.

### 3) (Optional) `SDRPreviewMetadataContractTests.test_export_tags_color_metadata_consistently()`
- Export a short deterministic clip.
- Probe metadata and assert consistent primaries/transfer/matrix.
- Gate this test if metadata behavior is intentionally platform-dependent.

## Production steps
1. Add graph-contract tests.
2. If tests fail, tighten TimelineCompiler graph assembly (IDT/ODT placement).
3. Add export metadata defaults and QC assertions (only if deterministic across machines).

## Definition of done
- Contract tests pass and protect against regressions.
- Any intentional exceptions are explicit and tested.
