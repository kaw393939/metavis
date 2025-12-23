# Sprint 24o — TASKS

## Goal
Move volumetric effects to half/quarter resolution with a high-quality upscale (MetalFX), keeping visuals acceptable.

## 1) Volumetric half/quarter-res path
- [ ] Add half-res (and optionally quarter-res) render path for volumetric passes.
- [ ] Ensure multi-resolution graph support (from Sprint 24j) is used (no ad-hoc hacks).

## 2) Upscale strategy
- [ ] Integrate MetalFX upscale for volumetric output.
- [ ] Validate against baseline visual output (no obvious ringing/ghosting).

## 3) VolumetricNebula alignment
- [ ] Align with VRS/early termination strategy where feasible.
- [ ] Measure perf wins on M3+.

## Acceptance
- [ ] Representative volumetric graphs run faster on M3+.
- [ ] Visual output remains stable and acceptable.
