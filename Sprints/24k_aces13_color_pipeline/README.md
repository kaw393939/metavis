# Sprint 24k — ACES 1.3 + Tone Scale correctness

## Goal
Make “cinema-grade” color **repeatable and testable** for a solo creator workflow (iPhone + Mac) by matching ACES 1.3 behavior where research flags gaps, while preserving the ACEScg working-space contract.

This sprint is **validator-first** and assumes **Option A: iPhone Log** as the primary capture path.

## Docs
- ARCHITECTURE: `ARCHITECTURE.md`
- INTEGRATION (keep system working): `INTEGRATION.md`
- SPEC: `SPEC.md`
- DATA DICTIONARY: `DATA_DICTIONARY.md`
- TDD PLAN: `TDD_PLAN.md`
- TASKS: `TASKS.md`
- FINDINGS: `FINDINGS.md`

## Current status (as of 2025-12-23)
Sprint 24k has moved from “implement ACES in bespoke shaders” to a **reference-first Studio pipeline** using **official ACES 1.3 OCIO → baked LUT artifacts**.

### What is now true (shipping behavior)
- Working space contract remains: internal graph processing is **linear ACEScg**.
- `TimelineCompiler` appends exactly one terminal ODT node and makes it the graph root.
- `RenderPolicyTier.studio` prefers the **LUT-based** display ODTs when resources are available:
  - SDR: ACES 1.3 display rendering (OCIO-baked 33³ `.cube`)
  - HDR PQ1000: ACES 1.3 display rendering (OCIO-baked 33³ `.cube`)
- `creator/consumer` may still use faster/legacy shader paths where appropriate; Studio is the normative reference.

### Reference chain (what we treat as “truth”)
`official ACES 1.3 OCIO config` → `ociobakelut` → committed `.cube` LUT resources → GPU `lut_apply_3d`.

We validate the chain in two ways:
1) **Artifact integrity:** opt-in test re-bakes LUTs from the OCIO config and asserts the payload matches committed resources.
2) **GPU correctness:** opt-in Studio test compares GPU LUT output to CPU evaluation of the same LUT (apples-to-apples).

## Protocol: performance + color (historical, repeatable)
We now have a single command that runs baseline perf + memory + color-cert, and writes a timestamped run folder under `test_outputs/metrics/`.

### One-command runner
- `scripts/run_metrics.sh`
- Typical usage:
  - `scripts/run_metrics.sh` (auto run id)
  - `scripts/run_metrics.sh --run-id before_opt_01`
  - `scripts/run_metrics.sh --perf-sweep --sweep-repeats 3`
  - `scripts/run_metrics.sh --ocio-ref` (adds OCIO re-bake equivalence tests)

### Output layout
- Per-run artifacts:
  - `test_outputs/metrics/<RUN_ID>/summary.md`
  - `test_outputs/metrics/<RUN_ID>/events.jsonl`
  - `test_outputs/metrics/<RUN_ID>/swift_test.log`
- Global append-only log (all runs):
  - `test_outputs/perf/perf.jsonl`
- Index of all runs:
  - `test_outputs/metrics/README.md`

### What to do during optimization
When you change a shader/graph/policy:
1) Run `scripts/run_metrics.sh --run-id <meaningful_tag>`
2) Compare `summary.md` across runs (1080p/4K/8K when sweep is enabled)
3) Only accept perf wins if the Studio reference checks remain stable.

## Implementation map (where this lives in code)
### LUT artifacts (SwiftPM resources)
- `Sources/MetaVisGraphics/Resources/LUTs/aces13_sdr_srgb_display_rrt_odt_33.cube`
- `Sources/MetaVisGraphics/Resources/LUTs/aces13_hdr_rec2100pq1000_display_rrt_odt_33.cube`

### LUT loading
- `Sources/MetaVisGraphics/LUTResources.swift` (stable accessors + path fallbacks)
- `Sources/MetaVisGraphics/LUTHelper.swift` (`.cube` parsing)

### Compiler + engine integration
- `Sources/MetaVisSimulation/TimelineCompiler.swift` (tier-aware ODT selection; Studio prefers LUT ODTs)
- `Sources/MetaVisSimulation/MetalSimulationEngine.swift` (PSO prewarm includes `lut_apply_3d`)

### Test protocols
- `Tests/MetaVisSimulationTests/Perf/` (perf + memory harness; JSONL logger)
- `Tests/MetaVisSimulationTests/ACESMacbethACEScgDeltaETests.swift` (scene-referred ACEScg correctness)
- `Tests/MetaVisSimulationTests/ACESMacbethDeltaETests.swift` (display-referred + Studio LUT match)
- `Tests/MetaVisSimulationTests/ACESOCIOBakeReferenceTests.swift` (OCIO re-bake equivalence; opt-in)

### One-command metrics runner
- `scripts/run_metrics.sh` (writes `test_outputs/metrics/<RUN_ID>/...`)
- `scripts/summarize_metrics.py` (generates `summary.md` + run index)

## Coverage
- Matrix of all owned files: [shader_archtecture/COVERAGE_MATRIX_24H_24O.md](shader_archtecture/COVERAGE_MATRIX_24H_24O.md)

### Owned files (primary)
- Color pipeline shaders:
  - [Sources/MetaVisGraphics/Resources/ACES.metal](Sources/MetaVisGraphics/Resources/ACES.metal)
  - [Sources/MetaVisGraphics/Resources/ToneMapping.metal](Sources/MetaVisGraphics/Resources/ToneMapping.metal)
  - [Sources/MetaVisGraphics/Resources/ColorSpace.metal](Sources/MetaVisGraphics/Resources/ColorSpace.metal)
  - [Sources/MetaVisGraphics/Resources/FormatConversion.metal](Sources/MetaVisGraphics/Resources/FormatConversion.metal)
  - [Sources/MetaVisGraphics/Resources/ColorGrading.metal](Sources/MetaVisGraphics/Resources/ColorGrading.metal)
  - [Sources/MetaVisGraphics/Resources/MaskedColorGrade.metal](Sources/MetaVisGraphics/Resources/MaskedColorGrade.metal)
- Supporting Swift glue:
  - [Sources/MetaVisGraphics/LUTHelper.swift](Sources/MetaVisGraphics/LUTHelper.swift)

## Targets (from research)
- `ACES.metal`: Implement full ACES 1.3 RRT/ODT chain, including "Sweeteners" (Red Modifier, Glow). Use analytical approximations where possible (see `shader_research/Research_ACES.md`).
- `ToneMapping.metal`: Deprecate Reinhard. Implement ACES Single Stage Tone Scale (SSTS) as the default. See `shader_research/Research_ToneMapping.md`.
- `ColorSpace.metal`: Rewrite sRGB and PQ transfer functions using `select()`/`mix()` for branchless SIMD execution. See `shader_research/Research_ColorSpace.md`.
- `MaskedColorGrade.metal`: Switch to HCV color model for branchless hue adjustments.

## Key decisions
- **Studio correctness is defined by authoritative artifacts** (OCIO-baked LUTs), not bespoke shader approximations.
- Validation is opt-in and report-oriented (color-cert + perf logging) so the main suite stays fast.

## Architecture constraints (shipping contracts we must respect)
- 24h shader registry + compilation domains: `shader_archtecture/REGISTRY.md`
- 24j RenderGraph contracts: `RenderNode.OutputSpec` + `RenderRequest.edgePolicy`
- Golden thread (today): `TimelineCompiler` inserts IDT per clip and appends exactly one ODT at the end; the ODT is the graph root.

## Canonical assets
- Reference assets live in `Tests/Assets/acescg/` (EXR + CTL).
- Real-world integration clip:
  - `Tests/Assets/VideoEdit/apple_prores422hq.mov`
  - Recorded via Blackmagic Cam on iPhone; metadata does not fully specify transfer, so treat as **integration regression** unless an explicit ingest profile is locked.

## Acceptance criteria
- No regressions in existing tests.
- Clear separation of:
  - working-space transforms (IDT/ODT)
  - creative tone scale / sweeteners
- Documented parameterization + function naming stability.

## Next milestone (this sprint’s current focus)
Optimize the 1080p / 4K / 8K paths while keeping Studio as the reference truth and using policy tiers to control cost.
