# Sprint 24k — DATA DICTIONARY

This data dictionary defines the terms and artifacts Sprint 24k relies on.

## Color spaces
- **ACEScg (linear)**: internal working space for all compositing and grading.
- **ACES2065-1 (linear)**: interchange/reference space used by many published EXR references (including ColorChecker sets).
- **Rec.709 SDR**: display-referred output target for SDR masters.
- **PQ (ST 2084) 1000 nits**: display-referred output target for HDR masters.

## Transforms
- **IDT**: Input Device Transform. Maps camera encoding → ACEScg linear.
- **RGC**: Reference Gamut Compression.
- **RRT**: Reference Rendering Transform.
- **ODT**: Output Device Transform (SDR Rec.709, HDR PQ1000).
- **LMT**: Look Modification Transform (creative, optional).

## Assets
### Canonical reference assets
Location: `Tests/Assets/acescg/`
- `exr/ColorChecker*_ACES2065-1*.exr`: reference patch images in ACES2065-1.
- `ctl/*.ctl`: Academy CTL library files used as reference inputs for golden generation.

### Real-world integration footage
Location: `Tests/Assets/VideoEdit/`
- `apple_prores422hq.mov`: iPhone 16 Pro Max clip recorded via Blackmagic Cam.
  - Observed via `ffprobe`: ProRes 422 HQ, 10-bit 4:2:2, primaries tagged BT.2020, transfer unspecified.
  - Capture setting (operator-confirmed): **Apple Log (HDR)**.
  - Used for: pipeline integration regression (ingest → render → export), banding/flicker checks.
  - Not used as numeric ground truth unless capture profile is explicitly declared and locked (we should prefer the operator-declared profile over container tags).

Sidecar (authoritative ingest declaration):
- `Tests/Assets/VideoEdit/apple_prores422hq.mov.profile.json`

## Goldens
- **Golden image**: stored output image used as a reference for tests.
- **CTL-derived golden**: golden generated from reference CTL pipeline for a given input.
- **Baseline golden**: existing in-repo golden retained temporarily for continuity.

## Metrics
- **ΔE**: perceptual color difference metric used for ColorChecker patch validation.
- **Ramp tint**: deviation of neutral ramp chroma from expected near-zero.
- **Banding heuristic**: detects quantization steps in smooth gradients.

## Policy tier bounds
- **Tier tolerance**: max allowed deviation vs `studio` reference outputs.
  - Defined per test family (ColorChecker, ramps, HDR highlight roll-off).
