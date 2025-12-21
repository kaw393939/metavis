# Sprint 16 — TDD Plan (Auto Color Correct)

## Tests (write first)

### 1) `AutoColorCorrectorTests.test_respects_avoidHeavyGrade_descriptor()`
- Build a minimal sensors fixture with `avoid_heavy_grade=true`.
- Assert output grade is conservative (bounded parameter magnitudes).

### 2) `AutoColorCorrectorTests.test_deterministic_outputs()`
- Same sensors in → same grade params out.

### 3) Integration: `AutoEnhanceE2ETests.test_color_recipe_generated_from_sensors()`
- Run sensors ingest on a deterministic short asset (or existing test clip).
- Generate grade recipe.
- Assert recipe encodes and is stable.

## Production steps
1. Implement `AutoColorCorrector` that maps sensors/descriptors → grade params.
2. Provide a stable schema for grade proposals (struct + Codable).
3. Wire into the Feedback Loop runner.

## Definition of done
- Deterministic grade proposal.
- Conservative behavior when confidence is low.
- Integration test green.
