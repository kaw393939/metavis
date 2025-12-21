# Implemented Features

## Status: Implemented

## Acceptance criteria (met)
- ✅ Feature manifests can declare an ordered list of passes.
- ✅ Passes declare explicit named inputs/outputs (named intermediates).
- ✅ Execution is deterministic (stable scheduling and wiring).
- ✅ At least one real multi-pass feature runs end-to-end on Metal.
- ✅ Backward compatible with single-pass manifests.

## Accomplishments
- **PassScheduler**: Topological sort of render passes implementation.
- **MultiPassFeatureCompiler**: Compiles manifest passes into `RenderNode` sequence.
- **Backward Compatibility**: Supports single-pass kernels seamlessly.
- **Multi-Input Passes**: Multi-pass compilation supports passes with multiple inputs (primary + named secondary inputs).
- **Texture Pooling**: `TexturePool` exists and is used by `MetalSimulationEngine` for intermediate reuse.
- **Test Coverage**:
	- `Tests/MetaVisSimulationTests/Features/MultiPassFeatureCompilerTests.swift` covers multi-pass + multi-input wiring.
	- `Tests/MetaVisSimulationTests/Features/MultiInputFeatureRenderE2ETests.swift` validates end-to-end render execution with multi-input features.
	- `Tests/MetaVisSimulationTests/Features/MultiPassBlurRenderTests.swift` validates end-to-end multi-pass blur against golden.
	- `Tests/MetaVisSimulationTests/Features/PassSchedulerTests.swift` validates topological scheduling.
	- `Tests/MetaVisSimulationTests/Features/ShaderRegistryTests.swift` validates logical→concrete resolution.
