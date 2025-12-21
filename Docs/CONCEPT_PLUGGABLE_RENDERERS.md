# Concept: Pluggable Renderers (The "Device Rack")

> **Idea**: If the Renderer is a Device, we can have a whole rack of them. We plug in the right machine for the job.

## 1. The Need for Specialization
A single monolithic "Renderer" is hard to optimize for every use case.
*   **The Mac Studio case**: Unlimited power, thermal headroom, 8K ProRes.
*   **The iPhone case**: Thermal constraints, battery life, HEVC hardware focus.
*   **The Vision Pro case**: Stereo rendering, Foveated rendering, 90fps min.

## 2. The Device Catalog

### A. The Generalists
1.  **`StandardMetalDevice`**: The workhorse. Balanced for quality/speed (macOS default).
2.  **`MobileMetalDevice`**: Optimized for iOS A-series chips. Aggressive tile-memory usage, lower precision buffers if needed to save battery.

### B. The Specialists
3.  **`RealityRenderDevice`**:
    *   **Specialty**: Spatial Computing.
    *   **Output**: Multiview HEVC (Stereo 3D) or USDZ Texture baking.
    *   **Features**: Foveated rendering support.
4.  **`AnalysisRenderDevice`**:
    *   **Specialty**: Computer Vision.
    *   **Output**: Semantic Segmentation maps, Depth maps, Saliency heatmaps.
    *   **Pipeline**: Skips beauty shaders (Bloom, Grain) to feed raw data to the AI.
5.  **`AudioRenderDevice`**:
    *   **Specialty**: Sound Design.
    *   **Output**: Multi-channel Audio functionality (no video processing).
    *   **Performance**: Extremely fast (no GPU overhead).

## 3. The "Smart Switching" Agent
The User shouldn't have to manually select drivers. The Agent handles the "Patch Bay."

**Scenario: "Send this to my Vision Pro."**
1.  **Agent**: "I need to render for Vision Pro."
2.  **Lookup**: Finds `RealityRenderDevice` in the catalog.
3.  **Action**:
    *   Unplugs `StandardMetalDevice` from the `Session`.
    *   Plugs in `RealityRenderDevice`.
    *   Sets properties: `fov: 100`, `stereo: true`.
    *   Executes `render()`.
4.  **Result**: A perfect spatial video, without the user knowing what "Multiview HEVC" means.

## 4. Implementation Strategy
All these devices conform to `SimulationEngineProtocol` (or `RenderDeviceProtocol`).

```swift
protocol RenderDevice: VirtualDevice {
    func connect(to timeline: Timeline) async throws
    func renderRange(_ range: TimeRange) async throws -> Asset
}
```

This makes the system **Future Proof**. When Apple releases a new "Neural Texture Engine", we just write a new `NeuralRenderDevice` and plug it in. Codebase stays clean.
