# Sprint 24l — Post Stack Fusion (bandwidth reduction)

## Goal
Reduce full-res passes by fusing lightweight ALU operations into fewer kernels/passes.

## Coverage
- Matrix of all owned files: [shader_archtecture/COVERAGE_MATRIX_24H_24O.md](shader_archtecture/COVERAGE_MATRIX_24H_24O.md)

### Owned files (primary)
- Post-stack effects and candidates for fusion:
	- [Sources/MetaVisGraphics/Resources/Bloom.metal](Sources/MetaVisGraphics/Resources/Bloom.metal)
	- [Sources/MetaVisGraphics/Resources/Halation.metal](Sources/MetaVisGraphics/Resources/Halation.metal)
	- [Sources/MetaVisGraphics/Resources/FilmGrain.metal](Sources/MetaVisGraphics/Resources/FilmGrain.metal)
	- [Sources/MetaVisGraphics/Resources/Vignette.metal](Sources/MetaVisGraphics/Resources/Vignette.metal)
	- [Sources/MetaVisGraphics/Resources/Lens.metal](Sources/MetaVisGraphics/Resources/Lens.metal)
	- [Sources/MetaVisGraphics/Resources/Anamorphic.metal](Sources/MetaVisGraphics/Resources/Anamorphic.metal)
	- [Sources/MetaVisGraphics/Resources/SpectralDispersion.metal](Sources/MetaVisGraphics/Resources/SpectralDispersion.metal)
	- [Sources/MetaVisGraphics/Resources/LightLeak.metal](Sources/MetaVisGraphics/Resources/LightLeak.metal)
	- [Sources/MetaVisGraphics/Resources/Watermark.metal](Sources/MetaVisGraphics/Resources/Watermark.metal)

## Candidates (from research)
- **Bloom.metal**: Implement "Dual Filtering" (Kawase) for energy-conservative bloom. Reuse the same downsample chain for **Halation** to save bandwidth. See `shader_research/Research_Bloom.md`.
- **Lens.metal**: Fuse Distortion + Vignette + Grain into a single pass to hide texture latency. Use Sparse Textures if resolution > 4K. See `shader_research/Research_Lens.md`.
- **LightLeak.metal**: Render at low-res (1/4) and upscale to save massive ALU. See `shader_research/Research_LightLeak.md`.
- **Vignette/Watermark**: Inline these simple mix operations into the final color grade or ODT pass.

## Work items
- Define a PostStack kernel contract (inputs/outputs/params/function constants).
- Implement minimal variants (on/off toggles) without exploding PSO count.
- Update compiler feature mapping so these can be compiled predictably.

## Acceptance criteria
- Lower pass count for common graphs.
- Same outputs (within acceptable tolerance) compared to the unfused pipeline.
