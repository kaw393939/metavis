# Sprint 24o — Volumetric half-res + MetalFX

## Goal
Move volumetric effects to half/quarter resolution with a high-quality upscale.

## Coverage
- Matrix of all owned files: [shader_archtecture/COVERAGE_MATRIX_24H_24O.md](shader_archtecture/COVERAGE_MATRIX_24H_24O.md)

### Owned files (primary)
- Volumetric shaders:
	- [Sources/MetaVisGraphics/Resources/Volumetric.metal](Sources/MetaVisGraphics/Resources/Volumetric.metal)
	- [Sources/MetaVisGraphics/Resources/VolumetricNebula.metal](Sources/MetaVisGraphics/Resources/VolumetricNebula.metal)

## Targets
- `Volumetric.metal`: half-res render + upscale via MetalFX
- `VolumetricNebula.metal`: align with VRS/early termination strategy where feasible (may require pipeline changes)

## Acceptance criteria
- A representative volumetric graph runs faster on M3+.
- Visual output remains stable and acceptable.
- Multi-resolution graph support from Sprint 24j is used.
