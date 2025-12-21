# Sprint 4 Audit: Feature Multipass

## Status: Fully Implemented

## Accomplishments
- **Multi-pass Execution Model**: Implemented `MultiPassFeatureCompiler` and `PassScheduler`.
- **Topological Sorting**: `PassScheduler` correctly handles dependency resolution between passes using Kahn's algorithm.
- **Named Intermediates**: Passes explicitly declare inputs and outputs, avoiding implicit state.
- **Backward Compatibility**: `FeatureManifest` supports both single-pass (`kernelName`) and multi-pass (`passes`) definitions.
- **Shader Registry**: `ShaderRegistry` allows mapping logical pass names to concrete Metal functions.
- **Multi-input passes**: Pass compilation supports multiple inputs (primary + named secondary inputs).
- **Texture pooling**: `TexturePool` exists and is used by `MetalSimulationEngine` for intermediate reuse.

## Gaps & Missing Features
- **Binding semantics documentation**: Multi-input binding follows a stable convention (primary port `input`, additional inputs by declared names). If future shaders require non-standard indices, add an explicit binding path.

## Performance Optimizations
- **Deterministic Scheduling**: Ensures that the render graph is built in a stable, predictable order every frame.

## Low Hanging Fruit
- Add a focused render test per new multi-input shader family to lock in binding conventions.

## Tests
- `Tests/MetaVisSimulationTests/Features/MultiPassFeatureCompilerTests.swift`
- `Tests/MetaVisSimulationTests/Features/MultiInputFeatureRenderE2ETests.swift`
- `Tests/MetaVisSimulationTests/Features/MultiPassBlurRenderTests.swift`
- `Tests/MetaVisSimulationTests/Features/PassSchedulerTests.swift`
- `Tests/MetaVisSimulationTests/Features/ShaderRegistryTests.swift`
