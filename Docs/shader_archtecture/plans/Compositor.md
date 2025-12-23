# Plan: Compositor (from Research_Compositor.md)

## Shipping touchpoints
- Research: `shader_research/Research_Compositor.md`
- Shader: `Sources/MetaVisGraphics/Resources/Compositor.metal` (`compositor_*`)
- Compiler emits compositor nodes: `Sources/MetaVisSimulation/TimelineCompiler.swift`
- Engine has output-index special-case: `texture(2)` for compositors.

## Issues identified in research
- Current compute compositing is DRAM bandwidth bound.
- Research recommends programmable blending in a render pipeline to exploit tile memory.

## RenderGraph integration

- Tier: Full
- Fusion group: Standalone
- Perception inputs: none
- Required graph features: Composition boundary; candidate for render pipeline / programmable blending.
- Reference: `shader_archtecture/RENDER_GRAPH_INTEGRATION.md` (Compositor)

## Holistic solution (fits 24m)
- Migrate compositing to render pipeline(s) with programmable blending.
- Keep compute fallback for environments where needed.

## Concrete changes
- Implement a render-path compositor:
  - draw full-screen quad
  - programmable blending reads destination from tile memory
- Preserve existing compositor semantics:
  - crossfade/dip/wipe
  - alpha blend / multi-layer
- Maintain the RenderGraph contract so TimelineCompiler doesn’t change semantics.

## Validation
- Pixel-diff tests for key transitions.
- Performance comparison on multi-layer/transition cases.

## Dependencies
- Sprint 24m.
