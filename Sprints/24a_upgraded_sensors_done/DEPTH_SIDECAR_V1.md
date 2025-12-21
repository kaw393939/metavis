# Depth Sidecar v1 (Sprint 24a)

**Status:** Implemented reader + tests (no Asset C required). Sprint 24a is DONE; alignment/relink remains deferred until Asset C exists.

This document defines a minimal **v1** depth sidecar format that is:
- deterministic
- simple to generate on iOS
- easy to stream/read on macOS
- explicit about dimensions, timing, and calibration

It intentionally avoids standardizing “depth-as-video” until we have real-world assets.

## Discovery (filename convention)
Given a movie at:
- `<base>.mov`

The depth sidecar candidates are searched in this order (see `DepthSidecarLocatorV1`):
- `<base>.depth.v1.mov` (future)
- `<base>.depth.v1.exr` (future)
- `<base>.depth.v1.bin` + `<base>.depth.v1.json` (**this spec**)
- `<base>.depth.v1/` directory (future)

## Container Pair
A depth sidecar is represented by two files:
- `<base>.depth.v1.json` (manifest)
- `<base>.depth.v1.bin` (raw frame data)

The `.bin` contains **frameCount** frames of raw depth pixels, tightly packed, in frame order.

## Pixel Formats
Supported `pixelFormat` values:
- `r16f` — IEEE 754 Float16 depth in meters (little-endian), stored as uint16 bit patterns
- `r32f` — IEEE 754 Float32 depth in meters (little-endian)

Invalid/missing depth should be encoded as `NaN` (preferred) or `0`.

## Timing Model
This v1 format uses a simple fixed-rate clock:
- `startTimeSeconds` (Double)
- `frameDurationSeconds` (Double)

Frame index for time $t$ is:
$$ i = \mathrm{clamp}\left(\left\lfloor \frac{t - start}{duration} \right\rfloor, 0, frameCount - 1\right) $$

This is sufficient for first integration and relink experiments. If VFR support is needed later, v2 can switch to per-frame timestamps.

## Calibration (optional, but reserved)
`calibration` is optional in v1, but reserved for future relink + accurate alignment.

If present, it must include:
- `intrinsics3x3RowMajor` (9 Doubles)
- `referenceWidth` / `referenceHeight` (Ints)

## Manifest Schema (v1)
Example:

```json
{
  "schemaVersion": 1,
  "width": 256,
  "height": 192,
  "pixelFormat": "r16f",
  "frameCount": 120,
  "startTimeSeconds": 0.0,
  "frameDurationSeconds": 0.033333333333,
  "dataFile": "AssetC.depth.v1.bin",
  "endianness": "little",
  "calibration": {
    "intrinsics3x3RowMajor": [
      500.0, 0.0, 128.0,
      0.0, 500.0, 96.0,
      0.0, 0.0, 1.0
    ],
    "referenceWidth": 256,
    "referenceHeight": 192
  }
}
```

## Reader API
The repo provides a reference reader:
- `DepthSidecarV1Reader`

Responsibilities:
- Parse manifest.
- Resolve `dataFile` relative to the manifest.
- Read a depth frame by index or by timestamp.
- Produce a `CVPixelBuffer` in a compatible depth pixel format.

Non-goals (v1):
- alignment validation against RGB
- proxy/full-res relink mapping
- compressed depth video tracks

