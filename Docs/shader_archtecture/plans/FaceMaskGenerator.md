# Plan: FaceMaskGenerator (segmentation mask)

Source research: `shader_research/Research_FaceMaskGenerator.md`

## Owners / entry points

- Shader: `Sources/MetaVisGraphics/Resources/FaceMaskGenerator.metal`
- Kernels:
  - `fx_generate_face_mask`

## Problem summary (from research)

- Procedural ellipse masks are poor approximations for real face boundaries.

## Target architecture fit

- Prefer Vision / CoreML segmentation on the Neural Engine.
- Keep shader as fallback/debug visualizer.

## RenderGraph integration

- Tier: Full
- Fusion group: MaskOps
- Perception inputs: preferred replacement is perception (Vision/NE)
- Required graph features: Today rect-derived; future: replace with perception source nodes.
- Reference: `shader_archtecture/RENDER_GRAPH_INTEGRATION.md` (FaceMaskGenerator)

## Implementation plan

1. **Introduce a Vision-based mask device**
   - Use `VNGeneratePersonSegmentationRequest` (or face/person segmentation model) to produce a mask.
   - Ensure output mask is `IOSurface` backed for zero-copy Metal interop.
2. **Interop to Metal**
   - Import `CVPixelBuffer` mask as `MTLTexture` via `CVMetalTextureCache`.
3. **Edge refinement**
   - Apply a small blur/feather to mask edges (prefer MPS blur).
4. **Fallback / debug mode**
   - Keep `fx_generate_face_mask` for debugging, unit tests, or when Vision is unavailable.

## Validation

- Visual: mask conforms to hairline/jawline better than ellipse.
- Performance: segmentation runs on NE; GPU overhead is mostly compositing + feather.

## Sprint mapping

- Primary: `Sprints/24m_render_vs_compute_migrations` (Vision/NE integration + GPU interop)
