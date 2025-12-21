# Legacy VFX & AI Mining: Deep Dive Results

## Executive Summary
A deep dive into the legacy `MetalVisCore` codebase has revealed a sophisticated set of rendering and procedural generation algorithms. Far from being "legacy" in quality, many of these implementations utilize high-end cinematic techniques (Disney BRDF, Jimenez Bloom, Golden Angle Bokeh) that should be foundational to `MetaVisKit2`. Additionally, a "node-graph interpreter" for procedural fields was discovered, offering a roadmap for a powerful node-based material and effect system.

## Key Findings

### 1. Advanced Physically Based Rendering (`PBR.metal`)
*   **Model**: Implements a subset of the **Disney Principled BRDF**.
*   **Features**:
    *   **Surfaces**: Base Color, Metallic, Roughness, Specular, Transmission (Glass), IOR.
    *   **Emission**: Physically based emission intensity.
    *   **Procedural Integration**: deeply integrated with noise functions; the shader itself can sample Perlin/Worley noise to modulate Roughness/Metallic maps on the fly.
*   **Math**:
    *   `SchlickFresnel` (Fresnel response).
    *   `GTR1` and `GTR2` (Generalized Trowbridge-Reitz distributions for specular lobes).
    *   `SmithG_GGX` (Geometric shadowing).
*   **Recommendation**: Adopt this exact lighting model for the `MetaVisMaterial` system.

### 2. High-Performance Bloom (`Bloom.metal`)
*   **Technique**: A dual-filter approach (features from Call of Duty / Jimenez).
*   **Downsample**: Uses a **13-tap Dual Filter** for smooth broad downsampling, combined with a **Karis Average** (1 / (1+Luma)) in the first pass to eliminate "fireflies" (flickering bright pixels).
*   **Upsample**: Instead of a standard 9-tap tent filter, it uses a **12-tap Golden Angle Spiral** distribution. This prevents the "square box" artifact common in cheaper blooms and creates high-quality, circular bokeh-like falloff.
*   **Composite**: Strictly energy-conserving additive blend with **dithering** to prevent banding in dark gradients.
*   **Recommendation**: This is a production-grade bloom. Port directly to `MetaVisGraphics` post-processing pipeline.

### 3. Procedural Generation & "The Graph" (`FieldKernels.metal`)
*   **Discovery**: The codebase contains a `fx_procedural_graph` kernel that acts as a **stack-based bytecode interpreter** for mathematical operations on the GPU.
*   **Capabilities**:
    *   Standard Ops: Add, Sub, Mul, Div, Sin, Cos, Pow, Mix.
    *   Noise Ops: Perlin, Simplex, Worley, FBM.
    *   Domain Ops: Warp (distortion), Rotate, Scale, Offset.
*   **Legacy**: It supported 64 nodes per graph.
*   **Recommendation**: This confirms the viability of a "Node Graph" user interface for `MetaVisKit2`, where the graph is compiled into a bytecode buffer and executed by a single generic Compute Kernel, rather than compiling unique Metal shaders for every user graph.

### 4. Cinematic Lens Effects (`Lens.metal`)
*   **Model**: Brown-Conrady Distortion.
*   **Integration**: Chromatic Aberration (Lateral Color) is physically coupled to the distortion. The shader calculates the radial distortion first, then offsets the Red and Blue channels proportionally to the square of the radius.
*   **Result**: Produces realistic lens fringing at the edges of the frame that matches the geometric distortion.
*   **Recommendation**: Essential for the "Cinematic" aesthetic goal.

### 5. Particle Simulation (`Particles.metal`)
*   **System**: A hybrid vertex/fragment approach.
*   **Vertex Shader Physics**: Handling motion directly in the vertex shader allows for substantial particle counts without complex compute simulation passes for simple effects.
    *   **Buoyancy**: Continuous upward drift.
    *   **Turbulence**: Uses **Curl Noise** (calculated via derivatives of Simplex noise) to create fluid-like swirling motion without fluid simulation.
*   **Shading**: Implements **Blackbody Radiation** (Kelvin -> RGB) for physically accurate fire/heat colors.

### 6. Data Visualization (`Visualizers/`)
*   **Knowledge Graph**: GPU-accelerated force-directed layout (Barnes-Hut) previously identified.
*   **Data Charts**: The `DataChartVisualizer` confirms a "hybrid" approach where geometry is calculated on CPU (for precision and text layout) but rendering and animation (growth, fading) facilitates high frame rates.

## Integration Plan for `MetaVisKit2`

### `MetaVisGraphics` Module
*   **Post-Processing**:
    *   Implement `BloomPass` using the Jimenez/Golden-Angle technique.
    *   Implement `LensDistortionPass` with Brown-Conrady and physical CA.
    *   Implement `FilmGrainPass` (from previous session).
*   **Materials**:
    *   Create `DisneyPBR` shader profile matching the legacy `PBR.metal`.

### `MetaVisFX` Module (New Proposed Module)
*   **Procedural Graph Engine**:
    *   Port `FieldKernels.metal`'s interpreter to a new `ProceduralGraphEvaluator` class.
    *   Define a Swift `GraphNode` struct and a compiler to flatten a node tree into the `Int32` buffer format required by the GPU.
*   **Particle System**:
    *   Port `Particles.metal` to a `ParticleEmitter` component.

### `MetaVisApp` (Editor Layer)
*   **Node Editor**: The existence of the GPU graph interpreter strongly suggests building a Node Editor UI to allow users to construct these effect graphs visually.

## Conclusion
The legacy features are highly relevant. The "mining" phase is complete and has yielded a comprehensive technical roadmap for the visual capabilities of `MetaVisKit2`. We move from "exploring" to "architecting".
