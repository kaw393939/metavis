# Sprint 30: Deterministic Math Kernel (FxPoint)

## Goal
Replace the engine's dependency on `Float32` with a custom `FxPoint` (16.16 Fixed Point) library to guarantee bit-exact rendering and simulation across different hardware (e.g., M1 vs M2 vs Cloud).

## Rationale
The current `MetaVisSimulation` engine relies on floating-point arithmetic. While performant, floating point is not strictly deterministic across different architectures and compiler optimizations. For a generative OS where "Code is Law", we need a "Physics Engine" that plays by exact rules.

## Deliverables
1.  **`FxPoint` Library:** A pure Swift struct wrapping `Int32` (16.16) with saturated arithmetic operators (`+`, `-`, `*`, `/`).
2.  **`FxVector3` / `FxMatrix4x4`:** Linear algebra types built on `FxPoint`.
3.  **`DeterministicEngine`:** A subclass or alternative to `MetalSimulationEngine` that enforces `FxPoint` for all CPU-side calculations (Time, Position, Layout).
4.  **Verification Test:** A test that runs a simulation on `Double` (Control) vs `FxPoint` (Test), verifying that `FxPoint` output is identical across two runs (even if simulated "architecture drift" involves rounding modes).

## Optimization: Deterministic Audio
*   **Manual Rendering Mode:** To guarantee `MetaVisAudio` aligns with `FxPoint` physics, the `AVAudioEngine` must be switched to `enableManualRenderingMode(.offline)`. This explicitly decouples the DSP clock from the wall-clock, preventing hardware buffer jitters from affecting the output signal.

## Out of Scope
- Porting *all* Metal shaders to fixed point (GPU will still use `half` or `float` for pixel blending, but the *parameters* sent to it must be deterministically computed).
