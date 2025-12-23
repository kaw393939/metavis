# 24J Shader Architecture Plan (holistic)

This is the implementation-focused architecture plan that turns the research notes in `shader_research/` into a coherent set of changes.

## North stars
- **Correctness first**: ACEScg working space contract remains the golden thread.
- **Bandwidth is the bottleneck** for full-res frames (4K/8K). Prefer pass fusion and tile-memory paths.
- **Use Apple silicon accelerators when they win**: MPS for convolutions/filters; MetalFX for scaling; Vision/NPU for segmentation.
- **Stability**: Kernel names + binding indices remain stable unless deliberately versioned.

## System architecture decisions (what changes)

### A) Make the render graph explicitly multi-resolution
Research repeatedly asks for half/quarter res intermediates (bloom pyramid, volumetric, light leaks).
- Add a first-class concept of **resolution domains** per node/pass:
  - full-res
  - half-res
  - quarter-res
  - fixed-res (e.g. 256x256 scope)
- Extend `RenderNode` (or `RenderGraph` compilation) to carry desired output size.
- Teach `MetalSimulationEngine` texture allocation to honor per-node resolution.

Status (implemented in 24j):

- `RenderNode.OutputSpec` supports `resolution` and a minimal `pixelFormat` contract.
- `MetalSimulationEngine` allocates outputs at per-node resolution.
- Mixed-resolution edges are supported via `RenderRequest.edgePolicy`:
  - `.autoResizeBilinear` (default) inserts `resize_bilinear_rgba16f` in the engine.
  - `.requireExplicitAdapters` emits a warning and continues.

### B) Introduce “post stack fusion” as an explicit design
Research recommends fusing lightweight, bandwidth-heavy passes:
- **Fuse** Vignette into ToneMapping/ODT.
- Optionally fuse **Lens + Vignette + Grain** into a single distortion/post pass to hide dependent texture-read latency.

Implementation pattern:
- Create a single **PostStack** kernel (or small set of variants) with function constants:
  - vignette on/off
  - grain on/off
  - watermark on/off
  - lens distortion on/off
  - chromatic aberration on/off

Status (deferred):

- PostStack kernel variants + compiler wiring are owned by Sprint 24l.

### C) Prefer render pipeline for compositing / clears when tile memory wins
Research calls out that some work should not be compute:
- **Compositor** should migrate from compute to a render pipeline using programmable blending.
- **ClearColor** and **DepthOne** should be replaced by render pass clear load actions.

Status (deferred):

- Render-vs-compute migrations are owned by Sprint 24m.

### D) Prefer MPS/MetalFX for well-known primitives
- **Blur**: replace custom gaussian with `MPSImageGaussianBlur` (or MPS box blur building blocks).
- **FaceEnhance**: use `MPSImageGuidedFilter` if available and acceptable.
- **Temporal**: prefer `MTLFXTemporalScaler` (or make custom viable by adding motion vectors + reprojection).
- **Volumetric**: half-res + upscale via `MTLFXSpatialScaler`.

Status (deferred):

- MPS/MetalFX swaps are owned by Sprint 24i / 24o depending on subsystem.

### E) Reduce global atomics with hierarchical reductions
- QC fingerprint accumulation should be rewritten as wave → threadgroup → global reduction.
- Waveform already uses a 2-pass approach; tune it using the same principles.

Status (deferred):

- QC reductions are owned by Sprint 24n.

## Integration points (current code)
- Registry of call paths and ownership: `shader_archtecture/REGISTRY.md`
- Timeline compilation: `Sources/MetaVisSimulation/TimelineCompiler.swift`
- Engine binding and output-index exceptions: `Sources/MetaVisSimulation/MetalSimulationEngine.swift`

## Deliverable structure
- Per-shader detailed plans live in `shader_archtecture/plans/*.md`.
- Sprint 24j+ folders each own a coherent slice of implementation.

## Global acceptance criteria
- ACEScg contract remains intact: IDT → working-space FX → compositor → ODT.
- Fewer full-res passes for the same timeline graph.
- Measurable M3+ improvements where research expects them (bandwidth, atomics, pass count).
- Tests updated/added for graph compilation + binding stability.
