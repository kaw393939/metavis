# Sprint 24j — Architecture Notes (RenderGraph multi-resolution + edge policy)

## Scope of 24j
24j implemented the minimum **runtime and data-model contracts** needed to safely run a RenderGraph that contains **mixed-resolution branches** (full/half/quarter/fixed), without breaking existing binding conventions.

This sprint is a foundation sprint for later work (24l/24m/24o) that needs:
- multi-resolution nodes,
- deterministic edge adaptation,
- conservative pixel-format handling for float-authored compute kernels.

## Architecture overview
### End-to-end path (frame render)
1. **Timeline authoring / feature selection** produces a set of effects.
2. **TimelineCompiler** compiles that into a `RenderGraph` DAG of `RenderNode`s.
3. **MetalSimulationEngine** executes the graph:
   - allocates node outputs (now resolution-aware),
   - binds input textures per node binding rules,
   - enforces edge compatibility policy (optionally inserting an adapter),
   - dispatches compute kernels.

### Where 24j changes live
- Data model additions:
  - `RenderNode.OutputSpec` (resolution + pixel format)
  - `RenderRequest.edgePolicy` (mixed-resolution edge policy)
- Runtime behavior:
  - `MetalSimulationEngine` allocates textures per-node output size
  - `MetalSimulationEngine` adapts mismatched input sizes according to `edgePolicy`
  - `MetalSimulationEngine` conservatively allows non-float output formats only at safe terminals
- Shader enablers:
  - `resize_bilinear_rgba16f` in `FormatConversion.metal` (engine-inserted adapter)

## Core concepts
### 1) Node output contract (resolution + pixel format)
Each `RenderNode` may specify an `output` contract:
- **Resolution**: `.full`, `.half`, `.quarter`, `.fixed`
- **Pixel format**: `.rgba16Float` (default working format), plus selected non-float formats

If `output` is absent, the engine treats the node as **full-resolution** output.

### 2) Mixed-resolution edges are a policy decision
24j introduced a request-level policy that applies during execution:
- `.requireExplicitAdapters`
  - the engine does not resize for you;
  - it records a warning when an input size mismatches the consuming node’s output size.
- `.autoResizeBilinear`
  - the engine auto-inserts a bilinear resize step using `resize_bilinear_rgba16f`.

### 3) Mask edges are special-cased (today)
The engine currently skips auto-resize for input keys `mask` and `faceMask` because existing shaders sample masks in normalized coordinates and do not require identical pixel dimensions.

This is an intentional “current pipeline reality” rule. If future shaders start assuming 1:1 mask pixel grids, this rule must be revisited.

### 4) Pixel format contract is conservative by default
Most compute kernels are authored against float textures. To prevent runtime/type mismatches and downstream incompatibilities:
- The engine defaults intermediates to `rgba16Float`.
- Non-float outputs are only allowed when:
  - the node is terminal (no downstream consumers), and
  - the requested non-float format is explicitly supported for terminal outputs, and
  - the caller allows it (via the engine’s terminal-output allowance used by export paths).

When a non-float request is not allowed, the engine overrides to `rgba16Float` and records a warning.

## Execution invariants (24j)
- Output texture size is deterministic from `(baseWidth, baseHeight)` and `OutputSpec`.
- Mixed-resolution edges are never silently broken:
  - either resized (policy `.autoResizeBilinear`), or
  - warned (policy `.requireExplicitAdapters`).
- Adapter kernels are never applied recursively to themselves.
- Masks/face masks do not trigger resize insertion under the current convention.

## Design decisions + non-goals (24j)
## Ideology / Principles (24j)
24j is intentionally “plumbing-first”. The point is to make later shader work faster and safer by making the graph/runtime contracts explicit.

### Principles
- **Contracts over conventions:** if the engine assumes something (sizes, formats, bindings), we represent it in data structures and/or enforce it.
- **Determinism over cleverness:** sizing and adaptation decisions must be predictable and testable.
- **Conservative correctness before optimization:** float intermediates and safe defaults prevent subtle regressions; perf work comes after we can *measure* confidently.
- **Warnings as observability:** when we choose not to fail, we still emit structured warnings so we can tighten later.
- **Graph portability:** a `RenderGraph` should be executable in multiple contexts (preview/export) with different strictness levels.

### What this enables downstream
- 24l: fuse ALU-only post steps without breaking sizing/format contracts.
- 24m: migrate selected stages to render passes while preserving graph semantics.
- 24o: run volumetrics at half/quarter res and upscale cleanly.

### Anti-patterns (avoid)
- **Silent, implicit resizes that change look:** resizing is allowed only as an explicit adapter behavior under policy (and must be observable).
- **Auto-resizing masks for pixel-space algorithms without declaring it:** if a mask is used in pixel space, make alignment explicit via adapters/variants.
- **Allowing non-float intermediates “because it seems faster”:** only do 8-bit intermediates when kernels are authored for them and conversions are explicit.
- **Per-node policy knobs that fragment execution:** prefer request-level policy so the same graph can run in preview/export with controlled strictness.
- **Mixing semantic effects into adapters:** an adapter should only satisfy compatibility (size/format), not add creative transforms.
- **Breaking binding conventions implicitly:** any binding/index special-cases must be documented and tested.

## Design decisions + non-goals (24j)
### Decisions (why the design looks like this)
- **Request-level edge policy (not per-node):** keeps graphs portable and lets export/playback choose strictness without rewriting the graph.
- **Engine-inserted resize is an adapter, not a semantic effect:** `resize_bilinear_rgba16f` exists to satisfy edge compatibility, not to change look.
- **Mask inputs skip resize insertion:** current mask sampling is normalized; forcing size alignment would add bandwidth cost and can introduce subtle sampling shifts.
- **Float intermediates are the default contract:** most kernels are authored for float textures; forcing 8-bit intermediates would either break kernels or add extra conversion passes.
- **Non-float outputs are restricted to safe terminals:** avoids downstream type/precision mismatches and keeps the working space stable.

### Non-goals (explicitly out of scope for 24j)
- **No new effect semantics:** 24j changes plumbing/contracts only; it does not change the look of effects.
- **No shader fusion:** pass-count reduction belongs to 24l.
- **No render-vs-compute migration:** tile-memory wins belong to 24m.
- **No volumetric downscale/upscale wiring:** half/quarter-res volumetrics + MetalFX belong to 24o.
- **No color-science correctness changes:** ACES/tone scale work belongs to 24k.

### Known tradeoffs (accepted for now)
- **Resize is bilinear and float-only:** good enough as an adapter; higher-quality resampling and non-float adapters can be added later if needed.
- **Warnings are preferred over hard failures in strict mode:** `.requireExplicitAdapters` currently warns; if we later want a “fail-fast” mode, that should be a new policy case.

## Future extensions (deliberately not implemented in 24j)
This section is here so future work doesn’t accidentally “fight” 24j’s intent.

### Edge policy evolution
- Add `failFastOnMismatch`: throw when an edge is incompatible (useful for CI/export correctness gates).
- Add adapter selection beyond bilinear:
  - nearest / bicubic / Lanczos (quality tiers)
  - color-aware downsample (box/mitchell) for energy preservation
- Consider *per-edge* overrides only if needed for special cases (e.g., masks) — prefer keeping the policy request-level.

### Mask semantics
- If we introduce any kernel that assumes 1:1 mask pixel alignment (e.g., morphological ops in pixel space), we should:
  - either remove the “skip resize for mask keys” rule, or
  - introduce explicit mask-space adapters (with clear naming like `mask_resize_*`).

### Pixel format contract evolution
- If we want 8-bit intermediates for bandwidth savings, do it as a deliberate pipeline mode:
  - explicit conversion nodes,
  - explicit kernel variants that read/write 8-bit textures,
  - tests proving determinism/tolerance.
- Add explicit support for `r8Unorm` terminal outputs where appropriate (e.g., exporting masks), once export paths are validated.

### Multi-resolution graph ergonomics
- Add helper nodes/types for “branch at half res, then upscale and merge” patterns so authors don’t have to hand-roll glue.
- Extend the registry/compiler to tag which effects are safe/ideal at half/quarter res.

### Adapter kernel placement
- Today the adapter is inserted at runtime. If we need tighter control/visibility, we can instead (or additionally) insert explicit adapter nodes during compilation.

## Error + warning surfaces
24j relies on warnings for non-fatal contract issues:
- `size_mismatch ... (insert resize_bilinear_rgba16f)` when `.requireExplicitAdapters` encounters mismatched sizes
- `auto_resize ... WxH->WxH` when `.autoResizeBilinear` inserts an adapter
- `output_format_override ... requested=... using=rgba16Float` when the engine refuses a non-float intermediate

Hard failures can occur if the adapter PSO is missing when needed.

## Test coverage (24j)
24j added unit tests to lock in these contracts:
- OutputSpec size resolution
- Resize adapter node behavior
- Auto-resize edge policy behavior
- Require-explicit-adapters edge policy behavior
- Terminal output pixel format override behavior

