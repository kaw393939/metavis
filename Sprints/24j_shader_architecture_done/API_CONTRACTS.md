# Sprint 24j — API + Contracts

This document summarizes the public API surfaces and the behavioral contracts that 24j established.

## Public API surfaces (Swift)
### RenderNode.OutputSpec
Located in `Sources/MetaVisCore/RenderGraph.swift`.

- `OutputSpec.Resolution`
  - `.full | .half | .quarter | .fixed`
- `OutputSpec.PixelFormat`
  - `.rgba16Float | .bgra8Unorm | .rgba8Unorm | .r8Unorm`
- `init(resolution:pixelFormat:fixedWidth:fixedHeight:)`

#### Deterministic helpers
- `RenderNode.resolvedOutputSize(baseWidth:baseHeight:) -> (width:Int, height:Int)`
  - Pure function used by runtime + tests.
- `RenderNode.resolvedOutputPixelFormat() -> OutputSpec.PixelFormat`

### RenderRequest.edgePolicy
Located in `Sources/MetaVisCore/RenderRequest.swift`.

- `RenderRequest.EdgeCompatibilityPolicy`
  - `.requireExplicitAdapters`
  - `.autoResizeBilinear`
- `RenderRequest.init(..., edgePolicy: EdgeCompatibilityPolicy = .autoResizeBilinear)`

## Runtime contracts (MetalSimulationEngine)
Located primarily in `Sources/MetaVisSimulation/MetalSimulationEngine.swift`.

### Contract: output allocation honors OutputSpec resolution
For each node, the engine resolves `(width,height)` from the base size and allocates an output texture of that size.

### Contract: edge policy governs size mismatches
When binding inputs, if an input texture size differs from the consuming node’s output size:
- If `edgePolicy == .requireExplicitAdapters`
  - do not resize; emit a warning describing the mismatch.
- If `edgePolicy == .autoResizeBilinear`
  - resize via `resize_bilinear_rgba16f` to match the consuming node’s size; emit a warning describing the resize.

### Contract: adapter insertion exclusions
The engine does not auto-insert resizes in these cases:
- the current node shader is the adapter itself (`resize_bilinear_rgba16f`)
- the input key is `mask` or `faceMask`

### Contract: pixel formats are conservative
The node’s requested pixel format is interpreted as an intent, not a guarantee.

Rules:
- `rgba16Float` is always allowed.
- Non-float formats are only allowed when the node is terminal (no downstream consumers) and the caller explicitly permits terminal non-float outputs.
- If a non-float request is rejected, the engine uses `rgba16Float` and emits an `output_format_override` warning.

## Shader contract (adapter)
Located in `Sources/MetaVisGraphics/Resources/FormatConversion.metal`.

### resize_bilinear_rgba16f
- input: `texture(0)` float sampled texture
- output: `texture(1)` float write texture
- sampling: normalized coordinates, linear filter, clamp-to-edge

This kernel is intended as a general-purpose adapter for multi-resolution edges where float intermediates are expected.

## Test contracts (what is locked in)
- OutputSpec size resolution behavior is deterministic.
- Auto-resize inserts adapters for non-mask inputs.
- Require-explicit-adapters never inserts adapters.
- Pixel format override behavior is stable (non-float intermediates overridden, safe terminal outputs allowed).

