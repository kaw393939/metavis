# Sprint 14 — TDD Plan (Dip/Wipe + Assets Coverage)

## Principles
- No mocks.
- Use real media files from `Tests/Assets`.
- Assertions must be semantic and deterministic (probe-based), not “export succeeded”.

## Test Matrix

### 1) Dip transition rendering
**Test:** `TransitionDipWipeE2ETests.test_dipToBlack_midpointIsNearBlack()`
- Inputs: two real MP4s from `Tests/Assets/genai/*`.
- Timeline: 2 clips overlapping via transitions.
- Transition: `.dipToBlack(duration: 0.6s)` on outgoing + matching `.dipToBlack(duration: 0.6s)` on incoming.
- Assertion: at overlap midpoint, `VideoContentQC.validateColorStats` reports `meanLuma` close to 0.

### 2) Wipe transition rendering
**Test:** `TransitionDipWipeE2ETests.test_wipeLeftToRight_midpointHasDifferentLeftRightRegions()`
- Inputs: two real MP4s from `Tests/Assets/genai/*`.
- Transition: `.wipe(direction: .leftToRight)` with duration 0.6s.
- Assertion: sample a decoded frame at overlap midpoint; compute mean luma for left and right regions; assert `abs(left-right)` is above a threshold.

### 3) Assets coverage (types)
**Test:** `AssetsCoverageE2ETests.test_allAssetsTypesAreExercised()`
- Enumerate extensions under `Tests/Assets`.
- Assert expected extension set includes: `mov`, `mp4`, `exr`, `fits`, `vtt`.
- For each extension, run a real operation:
  - mov/mp4: export 0.5–1.0s and run `VideoQC.validateMovie`.
  - exr/fits: export 0.5–1.0s from a still as a timeline clip and validate not-black via color stats.
  - vtt: export a deliverable from a session with a single file-backed clip that has a sibling `.captions.vtt`; assert the exported bundle contains `captions.vtt` and it parses/contains `WEBVTT`.

## Definition of Done
- All tests green locally.
- Failures clearly indicate: which transition, which asset type, and which probe failed.

