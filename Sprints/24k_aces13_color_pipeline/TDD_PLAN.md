# Sprint 24k — TDD PLAN

## Strategy
Validator-first:
1) Define reference behavior (ACES 1.3 SDR + HDR PQ1000).
2) Create goldens from reference sources.
3) Make `studio` match goldens.
4) Constrain `creator`/`consumer` to bounded error vs `studio`.

Implementation note (current):
- For display rendering, Studio reference behavior is defined via **OCIO-baked LUT artifacts** (ACES 1.3 config → `ociobakelut` → committed `.cube` → GPU `lut_apply_3d`).

## Test families
### A) Contract tests (already exist, extend)
- Ensure compiler inserts IDT/ODT and that the working space is ACEScg.
- Add explicit coverage for HDR PQ1000 selection.

Contract invariants to lock:
- Exactly one display ODT is appended and is the graph root.
- Default remains Rec.709 ODT unless an HDR display target is explicitly selected.

### B) Procedural determinism tests
- SMPTE bars, zone plates, ramps generated in-engine.
- Assertions:
  - deterministic hashes for `studio` outputs
  - no unexpected pipeline drift over time

### C) Reference image validation (EXR)
Inputs:
- `Tests/Assets/acescg/exr/ColorChecker*_ACES2065-1*.exr`
Assertions:
- sample patch regions → compare vs expected patch values (or CTL-derived reference)
- ΔE thresholds

### D) HDR highlight + roll-off validation
- Use a procedural HDR ramp scene (ACEScg) that spans above diffuse white.
- Assert PQ1000 output matches CTL-derived golden within tolerance.

Note: HDR validation should be introduced behind an explicit display-target selector so it does not destabilize existing SDR baselines.

## Standard run protocol
When implementing or optimizing anything in this sprint, capture results with:
- `scripts/run_metrics.sh --run-id <meaningful_tag>`

This writes a per-run report folder under `test_outputs/metrics/<RUN_ID>/` and appends events to `test_outputs/perf/perf.jsonl` for historical tracking.

### E) Real-world integration regression (ProRes)
Input:
- `Tests/Assets/VideoEdit/apple_prores422hq.mov`
Profile:
- `Tests/Assets/VideoEdit/apple_prores422hq.mov.profile.json`
Use:
- end-to-end ingest → timeline → export → decode
- detect banding/flicker regressions and gross color errors
Note:
- This clip’s transfer is not fully specified via metadata; treat as integration-only unless we lock an explicit ingest profile for it.

## Initial implementation order
1) Add/lock reference assets under `Tests/Assets/acescg/`.
2) Add CTL-derived golden generator (offline script) and store goldens.
3) Replace HDR “Reinhard-ish” default path with ACES 1.3 HDR ODT behavior.
4) Add metrics-based validator (ΔE + ramp tint/banding).
5) Introduce tier-bounds tests.

## Definition of done
- A minimal set of goldens proves SDR + HDR correctness.
- `studio` matches reference; other tiers stay bounded.
- Real-world ProRes clip passes integration checks.
