# Plan: ClearColor (from Research_ClearColor.md)

## Shipping touchpoints
- Research: `shader_research/Research_ClearColor.md`
- Shader: `Sources/MetaVisGraphics/Resources/ClearColor.metal` (`clear_color`)

## Issues identified in research
- Clearing via compute is inefficient on TBDR.

## Holistic solution
- Prefer render-pass loadAction clears for tile-local metadata clears.

## RenderGraph integration

- Tier: Full
- Fusion group: Standalone
- Perception inputs: none
- Required graph features: Simple source node; should be trivially allocatable.
- Reference: `shader_archtecture/RENDER_GRAPH_INTEGRATION.md` (ClearColor)

## Concrete changes
- Deprecate `clear_color` compute usage in the engine.
- Replace with:
  - `MTLRenderPassDescriptor.colorAttachments[...].loadAction = .clear`
  - `clearColor = ...`

## Validation
- Ensure empty-timeline output remains identical.
- Confirm no compute dispatch occurs for clears.

## Dependencies
- Sprint 24m.
