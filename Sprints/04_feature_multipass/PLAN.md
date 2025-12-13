# Sprint 04 — Feature Pipeline Semantics (Multi-pass)

## Goal

Add a minimal multi-pass execution model so features that require multiple kernels/passes can run deterministically. This is a prerequisite for motion graphics recipes (titles/intros) and advanced looks.

Spec reference: `research_notes/specs/motion_graphics_concept.md.resolved`
Legacy reference: `Docs/research_notes/legacy_autopsy_render_graph_vfx.md`
Optimization reference: `Docs/research_notes/legacy_autopsy_optimizations_apple_silicon.md`
metavis3 reference (shader/graph reality check): `Docs/research_notes/metavis3_fits_jwst_export_autopsy.md`

## Acceptance criteria

- A feature/manifest can declare an ordered list of passes (kernels).
- Each pass explicitly declares its input(s) and output (named intermediates), not “implicit ping-pong”.
- Execution composes passes deterministically (stable ordering, deterministic intermediate allocation, deterministic outputs for fixed inputs).
- At least one multi-pass feature is exercised end-to-end on real Metal execution.
- The pass model is compatible with future motion-graphics building blocks (2.5D stage, typography, emitters) without requiring a redesign of pass semantics.
- Pass execution supports an explicit mapping layer from a *logical* pass name to a *concrete* Metal function/pipeline (metavis3 uses this pattern for JWST composite and post).

## Motion graphics alignment (why this sprint matters)

From the motion-graphics concept, several foundational effects are inherently multi-pass:

- **Typography (SDF text):** generate glyph field/atlas → shade/fill → optional outline/glow → composite.
- **Post chains ("Glitch Title"):** displacement → chromatic aberration → optional grain/vignette.
- **2.5D compositor:** multi-layer composition often benefits from separate layer renders then composite passes.

Sprint 04 focuses only on the *execution model* for these chains: pass ordering, named intermediates, and deterministic evaluation.

## Architectural Risks & Mitigations (Added for v2)

### 1. Logical Name Stability (The "Recipe" Problem)

- **Risk:** If a user saves a recipe using `blur_v1` and we rename the kernel to `blur_v2`, their project breaks (or looks wrong).
- **Mitigation:** "Logical Names" must be treated as **Public APIs**.
    - We need a `ShaderRegistry` that aliases logical names (`std_blur`) to specific internal kernels (`gaussian_blur_optimized_v4`).
    - Recipes should bind to the *Logical Name* (semantic intent), not the Metal function name.

### 2. The "RenderNode" God Object

- **Risk:** Stuffing topography logic into `RenderNode` makes it bloated and hard to test.
- **Mitigation:** Introduce a lightweight `RenderGraph` or `PassScheduler` struct.
    - `RenderNode` holds data (inputs/uniforms).
    - `PassScheduler` calculates execution order and dependencies.

## Implementation outline (concrete)

This repo already has the pieces to make multi-pass real with minimal churn:

- `FeatureManifest` currently supports single-pass via `kernelName`.
- `RenderGraph` is a list of `RenderNode`s; `MetalSimulationEngine` executes nodes **in list order**.

Sprint 04 implementation plan:

1. Extend `FeatureManifest` with optional `passes` (backward compatible)

    - Add `passes: [FeaturePass]?` where each pass declares:
      - `logicalName` (stable API)
      - `function` (concrete Metal function name) OR `logicalName` + registry resolution
      - `inputs: [String]` (names: `source`, `blurred_h`, `person_mask`, etc.)
      - `output: String` (named intermediate)
    - Keep `kernelName` as the single-pass fallback for existing manifests/features.

2. Add a frame compiler/builder that expands a feature into multiple `RenderNode`s

    - Convert pass `inputs`/`output` names into `RenderNode.inputs` UUID links.
    - Ensure stable ordering via a `PassScheduler` topological sort (and error on cycles/missing intermediates).
    - Set `RenderNode.shader` to the **resolved concrete function name**.

3. Add `ShaderRegistry` for logical → concrete mapping

    - Provide a deterministic resolution path with actionable errors when a function is missing.
    - The engine can continue caching PSOs by concrete function name (`ensurePipelineState(name:)`).

4. Ship one real multi-pass feature (separable blur)

    - Use `fx_blur_h` then `fx_blur_v` from `Sources/MetaVisGraphics/Resources/Blur.metal`.
    - Manifest uses named intermediate `blur_tmp` between passes.

5. Deterministic intermediates (minimum viable)

    - Within a single frame, allocate intermediates deterministically in scheduler order.
    - Pooling/MTLHeap reuse is an optimization follow-on; Sprint 04 only requires deterministic allocation behavior.

## Explicit non-goals (Sprint 04)

- Adding a `Camera` to `MetaVisTimeline`.
- Implementing SDF text rendering.
- Implementing particle emitters/cloners or instancing.
- Adding a full node-graph UI/authoring model.

## Existing code likely touched

- `Sources/MetaVisSimulation/Features/FeatureManifest.swift` (extend schema to express passes)
- `Sources/MetaVisSimulation/Features/StandardFeatures.swift` (mark at least one feature as multi-pass)
- `Sources/MetaVisSimulation/MetalSimulationEngine.swift` (execute multiple kernels with intermediate targets)
- `Sources/MetaVisSimulation/Features/RenderNode+Manifest.swift` (node creation from manifest)

## Deterministic generated-data strategy

- Use a known input image generated procedurally (SMPTE/zone plate).
- Apply a multi-pass effect (e.g., blur H then V) and validate predictable output properties.

## Test strategy (no mocks)

- Render a single frame to an offscreen texture/pixel buffer.
- Validate by hashing a deterministic downsample of the output.
- Optional: export short clip and run QC (slower).

## Performance note (implementation guidance)

- Prefer deterministic named-intermediate allocation via a reusable pool (eventual `MTLHeap`-backed `TexturePool`) to avoid per-frame allocations.
- Use `.memoryless` transient render targets where intermediates are not sampled later (tile-memory win on Apple GPUs).

