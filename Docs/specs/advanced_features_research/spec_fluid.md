# Spec: High-Performance Fluid Simulation (Curl Noise)

## 1. Objective
Implement a "fake fluid" simulation system capable of rendering smoke, fire, and liquid-like motion at 4K 60fps on Apple Silicon by avoiding expensive grid solvers in favor of **Curl Noise Turbulence**.

## 2. Technical Approach
Based on `metavis1/Sources/MetalVisCore/Shaders/Procedural/Particles.metal`.

### 2.1 The Physics Model
Instead of solving Navier-Stokes equations ($$\nabla \cdot u = 0$$), we construct a velocity field that is analytically divergence-free using the curl of a noise potential.

$$ \vec{v}(x) = \nabla \times \vec{\psi}(x) $$

Where $$\vec{\psi}(x)$$ is a vector potential field (e.g., 3D Perlin/Simplex noise).

*   **Advantages**:
    *   Implicitly incompressible (no "sink holes" or "sources").
    *   Infinitely detailed (limited only by noise octaves).
    *   Stateless (no need to store previous frame velocity grid).
    *   Massively parallel (Vertex Shader only).

### 2.2 Particle Behavior
*   **Buoyancy**: Particles rise based on explicit `RiseSpeed`.
*   **Turbulence**: Velocity is modulated by the Curl Noise field sampled at the particle's position.
    *   `pos += curl(pos * freq) * strength * dt`
*   **Blackbody Radiation**:
    *   Input: `Temperature` (Kelvin).
    *   Output: `RGB` color.
    *   Decay: Temperature cools over `Lifetime`, shifting color from Blue -> White -> Orange -> Red -> Black.

### 2.3 Rendering
*   **Additive Blending**: For fire/light.
*   **Alpha Blending**: For smoke/dust.
*   **Texture Support**: Gaussian point sprites or Smoke textures.

## 3. Implementation Plan
1.  **Noise Library**: Port `Noise.metal` (Simplex/Perlin) to `MetaVisGraphics/Shaders`.
2.  **Simulation Kernel**: Implement `particle_update` compute kernel (or keep as Vertex shader for simpler effects).
3.  **Emitter**: Create `ParticleEmitter` struct to configure: `SpawnRate`, `Lifetime`, `InitialVelocity`, `TurbulenceStrength`.

## 4. Acceptance Criteria
*   **Fluid Motion**: Particles should move in swirling eddies, not straight lines.
*   **Heat**: Fire particles should transition colors correctly (White hot -> Red cool).
*   **Performance**: 100,000 particles at 60fps on M1 Max.
