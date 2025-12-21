# Sprint 28: Fluid Dynamics (Curl Noise)

## Goal
Implement a high-performance "Fake Fluid" simulation using Curl Noise Turbulence to simulate smoke, fire, and organic particle motion without the cost of Navier-Stokes solvers.

## Rationale
Simulation is key to a "Generative" OS. Whether it's ambient dust motes or a raging fire transition, we need a particle system that feels "alive" and fluid, running at 60fps on Apple Silicon.

## Determinism Strategy
Fluid simulation on GPU (`Float32`) is inherently non-deterministic across architectures. To maintain the "Generative OS" promise:
1.  **Seed Control:** The `Noise` offset must be derived from a deterministic `FxPoint` seed on the CPU.
2.  **Emitter Logic:** The *spawning* of particles (position/velocity) must be calculated on CPU using `FxPoint` (Sprint 30) before being uploaded to the GPU buffers.
3.  **Visual Acceptance:** We accept that the specific pixel shape of the smoke may vary slightly on M1 vs M2, as long as the macro-behavior (position, color, lifespan) is locked by the CPU emitter.

## Deliverables
1.  **`Noise.metal`:** A port of Simplex/Perlin noise functions to Metal.
2.  **`CurlNoise` Kernel:** A function computing the analytical curl of the noise field (divergence-free velocity).
3.  **`ParticleSystem`:** A GPU-driven tailored emitter (Compute Shader) supporting Buoyancy and Turbulence.
4.  **Blackbody Shader:** Rendering particles with physical temperature colors (Kelvin -> RGB).

## Optimization: Apple Silicon M3
*   **Mesh Shaders:** On M3 and later, use `object` and `mesh` shaders to generate particle geometry. This allows sophisticated culling (frustum + density) before rasterization, significantly boosting 100k+ particle performance.
*   **Fallback:** Maintain a standard Compute+Vertex path for M1/M2.

## Sources
- `Docs/specs/advanced_features_research/spec_fluid.md`
