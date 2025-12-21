# Legacy Autopsy — Render Graph + VFX (metavis1 / metavis2)

## Scope
This note focuses on **render-graph orchestration** and **post/VFX pass execution** patterns worth porting into MetaVisKit2’s deterministic multi-pass foundation (Sprint 04) and later motion-graphics sprints.

Key legacy roots:
- metavis1: `Docs/research_notes/metavis1/Sources/MetalVisCore/Engine/Graph/*`, `.../Engine/Passes/*`, `.../Renderer/PostProcessingRenderer.swift`
- metavis2: `Docs/research_notes/metavis2/Sources/MetaVisRender/Engine/Graph/GraphPipeline.swift`, `.../Engine/TexturePool.swift`, `.../Engine/Graph/NodeGraphTypes.swift`

## metavis1 — Ordered pass list (“named texture registry”)

### What it is
- A `RenderPipeline` that executes an **ordered array** of `RenderPass` objects.
- Each `RenderPass` declares:
  - `inputs: [String]` (names looked up from a per-frame registry)
  - `outputs: [String]` (names allocated/registered for later passes)
- `RenderPipeline.render(context:)`:
  - resolves inputs by name
  - allocates outputs by name (creates `MTLTexture` per output name if missing)
  - calls `pass.execute(context:inputTextures:outputTextures:)`

Files:
- `Docs/research_notes/metavis1/Sources/MetalVisCore/Engine/Graph/RenderPipeline.swift`
- `Docs/research_notes/metavis1/Sources/MetalVisCore/Engine/Graph/RenderPass.swift`
- `Docs/research_notes/metavis1/Sources/MetalVisCore/Engine/Graph/RenderContext.swift`

### Notable mechanics worth reusing
- **Named intermediates** as the primary wiring model (inputs/outputs are explicit and stable).
- **Clear-before-use** on allocated outputs to avoid uninitialized VRAM artifacts.
- A simple **“final output selection”** policy (`display_buffer`, else last pass output).
- A timeline-driven parameter bridge:
  - `TimedEffectState` timeline
  - `RenderPipeline.applyEffectStates(at:)` mutates passes (or `PostProcessingPass.config`) before execution.

### Caveats / pitfalls to avoid when porting
- Allocation is currently “create texture if missing”; no reference counting or pooling in the pipeline.
- `PostProcessingRenderer.processHDR(...)` creates a dummy `RenderContext` using `CFAbsoluteTimeGetCurrent()` (non-deterministic time source). Deterministic multi-pass should always use frame time from the engine/timeline.

## metavis1 — Pass implementation patterns (examples)

### Fullscreen render pass wrapper
- `FullscreenPass` is a reusable **full-screen triangle** render encoder wrapper with optional uniform hook.
- Important detail: supports `.load` when doing “over” blending.

File:
- `Docs/research_notes/metavis1/Sources/MetalVisCore/Engine/Passes/FullscreenPass.swift`

### Compute-chain style passes
- `BloomPass` is a classic compute chain:
  - prefilter threshold → blur H → blur V → composite
  - allocates temporary textures internally (not ideal for perf, but structurally clear)

File:
- `Docs/research_notes/metavis1/Sources/MetalVisCore/Engine/Passes/BloomPass.swift`

### Temporal accumulation (subframes)
- `AccumulationPass` maintains a persistent accumulation texture, clears on first subframe, accumulates weighted samples, and resolves on the last subframe.
- Weight calculation is tied to the camera shutter model.

File:
- `Docs/research_notes/metavis1/Sources/MetalVisCore/Engine/Passes/AccumulationPass.swift`

### “Uber” post-processing pass
- `PostProcessingPass` delegates to `PostProcessingRenderer` (ACES/tonemap + bloom/halation/anamorphic + lens FX).
- Uses external command buffer and can write directly into an output texture.

Files:
- `Docs/research_notes/metavis1/Sources/MetalVisCore/Engine/Passes/PostProcessingPass.swift`
- `Docs/research_notes/metavis1/Sources/MetalVisCore/Renderer/PostProcessingRenderer.swift`

## metavis2 — Recursive node graph evaluation (“processing graph”)

### What it is
- A `NodeGraph` data model (nodes + connections + root node).
- `GraphPipeline` recursively evaluates nodes starting from `rootNodeId`:
  - evaluates upstream node inputs
  - dispatches a processor per node type (`.composite`, `.filter`, `.text`, `.bloom`, etc.)
- Special case: `.time` nodes create a **new RenderContext** with modified `time`, then evaluate upstream.

Files:
- `Docs/research_notes/metavis2/Sources/MetaVisRender/Engine/Graph/NodeGraphTypes.swift`
- `Docs/research_notes/metavis2/Sources/MetaVisRender/Engine/Graph/GraphPipeline.swift`
- `Docs/research_notes/metavis2/Sources/MetaVisRender/Engine/RenderContext.swift`

### Notable mechanics worth reusing
- A serious `TexturePool`:
  - MTLHeap-backed allocation
  - LRU-ish eviction + memory budget
  - helpers for `.private` intermediates, `.shared` textures, and `.memoryless` render targets

File:
- `Docs/research_notes/metavis2/Sources/MetaVisRender/Engine/TexturePool.swift`

### Caveats / pitfalls to avoid when porting
- Recursive evaluation without caching can re-evaluate shared subgraphs.
- The graph model is flexible, but deterministic multi-pass (Sprint 04) should *start* with an ordered pass list; node graphs can compile to ordered passes later.

## Recommended porting strategy into MetaVisKit2

### A) Sprint 04 (multi-pass foundation): borrow metavis1’s wiring semantics
- Use **ordered passes** with **named IO** exactly like metavis1’s `RenderPass(inputs/outputs)` model.
- Require pass manifests to declare:
  - ordered execution index
  - input names
  - output names
  - output descriptors (format/size/usage) so allocation is deterministic

### B) Early follow-up: adopt metavis2’s TexturePool semantics
- Add a texture pool with:
  - heap-backed allocation (Apple Silicon)
  - deterministic keying (descriptor → key)
  - explicit acquire/return (or ref-counted) lifetime
  - optional memoryless textures for on-tile render passes

### C) Timeline-driven parameterization (determinism)
- Keep metavis1’s idea (timeline → pass parameters), but make it compile-time/engine-driven:
  - parameters derived from `MetaVisTimeline` time
  - never from wall-clock
  - avoid pass-side internal “time now” calls

### D) Motion-graphics building blocks (post Sprint 04)
Treat the following as *multi-pass feature recipes* built on Sprint 04:
- Bloom chain (prefilter → blur → composite)
- Halation / bloom / grain / vignette as composable passes
- Lens distortion + chromatic aberration as a compute pass
- Temporal accumulation as an optional “subframe resolve” pass

## Concrete backlog items (draft)
- **Deterministic time invariant:** forbid wall-clock in render passes; add an audit test.
- **Pass descriptor schema:** ensure each output has an explicit descriptor; no implicit format defaults.
- **TexturePool port:** MTLHeap-backed pool with memory budget + LRU.
- **Reference post chain:** implement a minimal post chain as a multi-pass feature (bloom H/V + composite) and validate determinism.
- **Temporal accumulation feature:** port shutter-weighted accumulation as a multi-pass recipe.

## Suggested acceptance tests (mapping to MetaVisKit2)
- Given fixed input image + fixed parameters + fixed seed, multi-pass output hash matches golden.
- Output allocation determinism: intermediate names and descriptors are stable across runs.
- No wall-clock usage: time-dependent passes depend solely on `RenderContext.time`.
