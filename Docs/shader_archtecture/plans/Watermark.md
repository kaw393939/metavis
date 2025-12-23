# Plan: Watermark (from Research_Watermark.md)

## Shipping touchpoints
- Research: `shader_research/Research_Watermark.md`
- Shader: `Sources/MetaVisGraphics/Resources/Watermark.metal` (`watermark_diagonal_stripes`)

## Issues identified in research
- Branching in stripe logic can be replaced with branchless `step/mix`.

## Holistic solution
- Keep watermark as cheap ALU and optionally fuse into post stack if desired.

## RenderGraph integration

- Tier: Full
- Fusion group: Standalone (export-time)
- Perception inputs: none
- Required graph features: Output boundary; preserve alpha/format semantics.
- Reference: `shader_archtecture/RENDER_GRAPH_INTEGRATION.md` (Watermark)

## Concrete changes
- Replace `if` branching with `step` + `mix` (or `select`).

## Validation
- Confirm stripe pattern and opacity match.

## Dependencies
- Opportunistic (24l if fused).
