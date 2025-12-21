# MetaVisSimulation Assessment

## Initial Assessment
MetaVisSimulation is the "Body" of the system. It contains the `MetalSimulationEngine`, a high-performance GPU renderer that executes the `RenderGraph` defined by Core. It relies on `MetaVisGraphics` for kernels but owns the execution pipeline (Command Buffers, Texture Pooling).

## Capabilities

### 1. Metal Simulation Engine
- **Actor-based**: `MetalSimulationEngine` is an actor, ensuring serialized access to the GPU command queue.
- **Resource Pooling**: `TexturePool` recycles textures to minimize allocation overhead during playback.
- **Diagnostics**: Includes a debug logging system (writing to `/tmp`) and simple warning collection.

### 2. Timeline Compiler
- **Flattening**: Converts the hierarchical `Timeline` (tracks/clips) into a flat `RenderGraph` for a specific time.
- **Compositing**: Automatically handles transitions (Crossfade, Wipe) and multi-track blending.
- **Working Space**: Enforces ACEScg working space by injecting IDT (Input Device Transform) nodes for all inputs.

### 3. Resilience
- **Fallbacks**: If the Metal Library bundle fails to load, it attempts to compile shallow-embedded shader strings (`compileLibraryFromHardcodedSources`). This is great for testing but fragile for production.

## Technical Gaps & Debt

### 1. Hardcoded Shader Fallback
- **Issue**: `compileLibraryFromHardcodedSources` contains massive concatenated strings of C++ shader code inside the Swift file.
- **Debt**: Nightmare to maintain. If `MetaVisGraphics` changes, this fallback rots immediately.
- **Fix**: Remove hardcoded strings; enforce correct Bundle resource loading.

### 2. Naive Pixel Buffer Export
- **Issue**: `render(to cvPixelBuffer)` assumes simple format matching or uses hardcoded dispatch logic.
- **Risk**: Fails if exporting to a format not explicitly handled (e.g. 10-bit YUV).

## Improvements

1.  **Shader Management**: Formalize the library loading logic.
2.  **YUV Export**: Add proper RGB->YUV compute kernels for professional delivery formats.
