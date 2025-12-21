# Sprint 29: Cinematic Lens (VFX)

## Goal
Port the high-end post-processing chain from the legacy codebase to give the final image a "filmic" quality, including physically based bloom and lens distortion.

## Rationale
Raw graphical output looks digital and sterile. To achieve the "Masterpiece" look, we need to simulate the imperfections of a physical camera lens.

## Deliverables
1.  **Jimenez Bloom:** A Dual-Filter bloom implementation (Downsample/Upsample) with a Golden Angle Spiral blur for natural highlights.
2.  **Lens Distortion:** Brown-Conrady distortion shader to simulate barrel/pincushion effects.
3.  **Chromatic Aberration:** Spectral separation coupled with the distortion model.
4.  **Integration:** Add these as standard nodes in the `MetaVisSimulation` render graph.

## Optimization: Apple Silicon M3
*   **Dynamic Caching:** Use `.memoryless` render target descriptors for the intermediate Bloom Ping-Pong buffers. This keeps the massive bandwidth entirely on-chip.
*   **Accelerate:** For any CPU-side image pre-processing (lens dirt maps), use `vImage` (which uses AMX) for high-speed convolution.

## Sources
- `Docs/specs/advanced_features_research/legacy_vfx_extraction.md`
