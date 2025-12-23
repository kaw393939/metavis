# Sprint 24m — Render-vs-Compute migrations (tile memory wins)

## Goal
Move work that should be tile-local out of compute where the research indicates large bandwidth savings.

## Coverage
- Matrix of all owned files: [shader_archtecture/COVERAGE_MATRIX_24H_24O.md](shader_archtecture/COVERAGE_MATRIX_24H_24O.md)

### Owned files (primary)
- Migration targets:
	- [Sources/MetaVisGraphics/Resources/Compositor.metal](Sources/MetaVisGraphics/Resources/Compositor.metal)
	- [Sources/MetaVisGraphics/Resources/ClearColor.metal](Sources/MetaVisGraphics/Resources/ClearColor.metal)
	- [Sources/MetaVisGraphics/Resources/DepthOne.metal](Sources/MetaVisGraphics/Resources/DepthOne.metal)

## Targets
- `Compositor`: render pipeline + programmable blending
- `ClearColor`: render pass loadAction clear (deprecate compute kernel)
- `DepthOne`: depth loadAction clear (deprecate compute kernel)

## Acceptance criteria
- Compositing performance improves in multi-layer cases.
- Cleared attachments no longer dispatch compute.
- Engine retains a compute fallback path (if needed) behind a feature flag.
