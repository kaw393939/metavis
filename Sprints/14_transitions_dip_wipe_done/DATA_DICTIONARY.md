# Sprint 14 — Data Dictionary

## Transition Model
### `TransitionType`
- `cut`
- `crossfade`
- `dip(color: SIMD3<Float>)`
- `wipe(direction: WipeDirection)`

### `WipeDirection`
- `leftToRight`
- `rightToLeft`
- `topToBottom`
- `bottomToTop`

## Render Graph Parameters
### `compositor_dip`
- Inputs:
  - `clipA` (texture2d RGBA16F)
  - `clipB` (texture2d RGBA16F)
- Parameters:
  - `progress` (Float; 0..1)
  - `dipColor` (SIMD3; treated as float4 padded)
- Meaning:
  - `progress` < 0.5 fades A→dipColor
  - `progress` >= 0.5 fades dipColor→B

### `compositor_wipe`
- Inputs:
  - `clipA` (texture2d RGBA16F)
  - `clipB` (texture2d RGBA16F)
- Parameters:
  - `progress` (Float; 0..1)
  - `direction` (Float encoded int)
    - 0 = leftToRight
    - 1 = rightToLeft
    - 2 = topToBottom
    - 3 = bottomToTop

## Probes
### Color stats
From `VideoContentQC.validateColorStats`:
- `meanLuma` (0..1)
- `lowLumaFraction`, `highLumaFraction`
- `peakLumaBin` (0..255)

### Region luma probe (test-only)
- `leftMeanLuma`, `rightMeanLuma` computed from decoded BGRA pixels.

## Asset Types (Tests/Assets)
- `mov`: file-backed video (may include audio)
- `mp4`: file-backed video
- `exr`: still image decoded via ffmpeg into RGBA half
- `fits`: still image decoded via built-in FITS reader into RGBA half
- `vtt`: caption sidecar copied/normalized into deliverable bundle

