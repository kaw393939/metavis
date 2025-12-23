# Sprint 24k — INTEGRATION (keep the system working)

This sprint adds **new color capabilities** (ACES 1.3 correctness + HDR PQ 1000 nits) while keeping the existing system stable.

The key to “smooth” is to respect the shipping contracts established in Sprints 24h and 24j:
- 24h: the shader/feature registry and what is clip-compilable
- 24j: RenderGraph output contracts + edge compatibility policy
- Current reality: TimelineCompiler always inserts **IDT → (FX) → compositor → ODT** and the ODT is the graph root

## Non-negotiable invariants (shipping)
- Working space inside the graph is **ACEScg linear**.
- TimelineCompiler inserts an IDT for each clip before any clip FX.
- TimelineCompiler appends exactly one display ODT at the end and makes it the graph root.
- The executor may auto-insert resize adapters depending on `RenderRequest.edgePolicy`.

## Minimal-change integration strategy
### Phase 0 — Validator foundations (no rendering behavior changes)
- Lock canonical reference assets under `Tests/Assets/acescg/`.
- Add ingest sidecars for real-world footage (e.g. `apple_prores422hq.mov.profile.json`).
- Add new tests in a way that does not change existing defaults.

### Phase 1 — Add HDR output target (opt-in)
- Introduce a **display target selector** that does not disturb SDR defaults.
  - Example: `DisplayTarget.sdrRec709` (default) vs `DisplayTarget.hdrPQ1000`.
- Add a new ODT kernel (e.g. `odt_acescg_to_pq1000`) without removing `odt_acescg_to_rec709`.
- Update TimelineCompiler to select which ODT node to append based on the new selector.

Implementation mapping (today):
- Selector: `RenderRequest.DisplayTarget` (default `.sdrRec709`).
- Compiler hook: `TimelineCompiler.compile(... displayTarget: ...)` selects `odt_acescg_to_rec709` or `odt_acescg_to_pq1000`.
- Executor prewarm: `MetalSimulationEngine` caches `odt_acescg_to_pq1000`.

Important: `odt_acescg_to_pq1000` is a **runtime-safe placeholder** (it produces a PQ signal), but it is not yet the ACES 1.3 reference RRT/ODT chain. Phase 3 replaces the mapping with reference behavior.

**Compatibility rule:** If the selector is absent, keep the current behavior (ODT Rec.709).

### Phase 2 — Make Studio the reference truth
- `RenderPolicyTier.studio` becomes the normative “truth” for goldens.
- `creator/consumer` are allowed to approximate, but must remain within tolerances.
- Tiers must never intentionally change the creative look.

**Implementation status (2025-12-23):**
- Studio ODT selection now prefers **LUT-based** ODTs (OCIO-baked `.cube`) applied by GPU `lut_apply_3d`.
- This is wired through the existing compiler contract (ODT as root) without changing default SDR behavior.

### Phase 3 — Replace placeholders with ACES 1.3 behavior
- Studio reference display behavior is provided by OCIO-baked LUT artifacts.
- Remaining work is to decide how far we want to push **non-studio** tiers toward LUT parity vs analytic shader approximations.
- Keep shader helpers stable and avoid kernel churn in shared include files.

### Phase 4 — Tighten governance
- Add CI opt-in gate for color correctness (analogous to perf governance).
- Add “fail-fast” mode for edge mismatches if needed for export correctness.

## Where changes must land (so we don’t break execution)
- Compiler insertion points:
  - `Sources/MetaVisSimulation/TimelineCompiler.swift`
- ODT/transfer kernels today:
  - `Sources/MetaVisGraphics/Resources/ColorSpace.metal`
- Tone mapping kernels:
  - `Sources/MetaVisGraphics/Resources/ToneMapping.metal`
- Runtime compilation lists / PSO prewarm:
  - `Sources/MetaVisSimulation/MetalSimulationEngine.swift`

## What to re-run after each step
- Contract tests (must stay true): ACEScg working space insertion.
- A minimal vertical slice render test (SMPTE/Macbeth).
- Perf sanity on creator tier (use the existing perf sweep harness; HDR is opt-in until stable).

## Repeatable perf + color protocol (historical tracking)
Use the one-command runner:
- `scripts/run_metrics.sh`

It writes a per-run folder:
- `test_outputs/metrics/<RUN_ID>/summary.md`
- `test_outputs/metrics/<RUN_ID>/events.jsonl`
- `test_outputs/metrics/<RUN_ID>/swift_test.log`

And appends all events to:
- `test_outputs/perf/perf.jsonl`

This enables “optimize → re-run → compare” loops without manual copy/paste of console output.
