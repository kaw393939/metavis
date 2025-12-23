# Plan: ColorSpace (from Research_ColorSpace.md)

## Shipping touchpoints
- Research: `shader_research/Research_ColorSpace.md`
- Shader: `Sources/MetaVisGraphics/Resources/ColorSpace.metal` (IDT/ODT, transfer functions, scopes)
- Compiler inserts IDT/ODT: `Sources/MetaVisSimulation/TimelineCompiler.swift`

## Issues identified in research
- Transfer functions are piecewise and can cause divergence.

## RenderGraph integration

- Tier: Full
- Fusion group: FinalColor
- Perception inputs: none
- Required graph features: Owns IDT/ODT kernels today; should remain graph-level.
- Reference: `shader_archtecture/RENDER_GRAPH_INTEGRATION.md` (ColorSpace)

## Holistic solution (fits 24k)
- Use branchless/select-based transfer functions for SIMD utilization.
- Reserve minimax polynomial approximations for “preview” modes only if needed.

## Concrete changes
- Refactor transfer functions:
  - implement `select()`-based branchless piecewise logic, OR
  - add a validated polynomial approximation path gated by a quality/perf mode.
- Make correctness the default (polynomial path is opt-in if ever used).

## Validation
- Unit-level numeric tests where feasible:
  - known points on the curve (toe/breakpoints)
  - monotonicity
  - max error bounds if polynomial path exists

## Dependencies
- Sprint 24k.
