# Sprint 24j — Data Dictionary

This dictionary names the objects and invariants introduced/standardized by 24j.

## Graph primitives
### RenderGraph
A Directed Acyclic Graph (DAG) describing how to render a frame.
- `nodes`: array of `RenderNode`
- `rootNodeID`: the node that produces the final output

### RenderNode
A single operation in the graph.
- `id`: stable node identifier (UUID)
- `name`: human label
- `shader`: Metal kernel function name (compute) used for dispatch
- `inputs`: port name → upstream `RenderNode.id`
- `parameters`: scalar/struct-like inputs (key/value)
- `output`: optional `RenderNode.OutputSpec`
- `timing`: optional time range validity

## Output contract
### RenderNode.OutputSpec
An optional output contract that allows the graph to express:
- **resolution tier**, and
- **requested pixel format**.

If `output == nil`, the node is treated as full resolution with float output.

#### OutputSpec.Resolution
- `full`: same as base render resolution
- `half`: base/2
- `quarter`: base/4
- `fixed`: explicit width/height (or base if one is missing)

#### OutputSpec.PixelFormat
Declared output intent.
- `rgba16Float`: scene-linear working format (default)
- `bgra8Unorm`: common display/export format
- `rgba8Unorm`: common 8-bit RGBA
- `r8Unorm`: common 8-bit single-channel mask

Important: the **engine may override** non-float requests when unsafe (see contracts).

## Request-level policy
### RenderRequest
Canonical input for a frame render.
- `graph`: `RenderGraph`
- `time`: time value
- `quality`: quality profile
- `renderFPS`: optional cadence hint
- `edgePolicy`: `EdgeCompatibilityPolicy`

### EdgeCompatibilityPolicy
Policy for handling mismatched input sizes across edges:
- `requireExplicitAdapters`: do not resize; warn on mismatch
- `autoResizeBilinear`: auto insert bilinear resize step

## Runtime terms (engine)
### Base render size
The “full resolution” width/height for the frame render. `OutputSpec` sizes derive from this.

### Node size
The resolved `(width, height)` for a node, computed from base size + `OutputSpec`.

### Mixed-resolution edge
Any edge where an upstream texture size differs from the consuming node’s resolved size.

### Adapter (engine-inserted)
A runtime-inserted operation applied to an input texture to make it compatible with a consuming node.

In 24j the adapter is:
- `resize_bilinear_rgba16f` (float bilinear resize)

### Mask inputs (special-cased)
Inputs keyed as `mask` or `faceMask` are currently exempt from auto-resize insertion because shaders use normalized sampling.

## Warning vocabulary (engine)
Warnings are used to keep execution deterministic while flagging contract issues.
- `size_mismatch`: input size differs from node size
- `auto_resize`: engine inserted resize adapter
- `output_format_override`: requested pixel format overridden to float

