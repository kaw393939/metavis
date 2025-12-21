# Concept: Distributed Quality Architecture

> **Goal**: "Start with the Best (God Mode), but scale down to the Budget."
> Quality is not just a setting; it is a **Signal** that propagates across isolated modules.

## 1. The `QualityProfile` (The Contract)
Defined in `MetaVisCore`, this struct is the "Traveler" that visits every module.

```swift
struct QualityProfile {
    let name: String            // "Draft", "Master", "Daily"
    let fidelity: Fidelity      // .proxy (1/4 res), .full, .supersampled
    let colorDepth: ColorDepth  // .bits8, .bits10, .float16, .float32
    let format: ExportFormat    // .hevc, .prores, .openEXR
}
```

## 2. Distributed Responsibility

### A. The Scheduler (`MetaVisScheduler`)
*   **Role**: Traffic Control.
*   **Logic**:
    *   If `Quality == .Master`: This is expensive. Dispatch to `BackgroundWorker`. Maybe verify disk space.
    *   If `Quality == .Draft`: This is cheap. Dispatch to `InteractiveWorker` (High Priority).
*   **Isolation**: The Scheduler doesn't know *how* to render, only *cost*.

### B. The Simulation Engine (`MetaVisSimulation`)
*   **Role**: The Chef.
*   **Logic**:
    *   If `Quality == .Master`: Enable "Disney PBR" full raymarching, 64-sample Motion Blur, High-Res Textures.
    *   If `Quality == .Draft`: Disable Motion Blur, Use Half-Res Textures, Simplifed Lighting.
*   **Isolation**: The Engine doesn't know about file formats, only *Pixel math*.

### C. The Exporter (`MetaVisExport`)
*   **Role**: The Delivery Truck.
*   **Logic**:
    *   If `Quality == .Master`: Write `OpenEXR` sequence (Lossless).
    *   If `Quality == .Daily`: Write `H.264` (Compressed for easy sharing).
*   **Isolation**: The Exporter doesn't know about lighting or scheduling, only *Bytes*.

## 3. The "Budget" Metaphor
We expose this to the user/agent as a "Budget Allocation".

*   **Time Budget**: "I need this in 5 minutes." -> System selects `Quality.Draft`.
*   **Disk Budget**: "I have 1TB." -> System selects `Quality.Master`.
*   **Monetary Budget (Cloud)**: "Don't spend more than $5." -> System limits Cloud Render nodes.

## 4. Implementation Strategy
1.  **Start at the Top**: Build the `OpenEXR / float32` pipeline first. This ensures the "pipes" are big enough.
2.  **Scale Down**: Add logic to "downsample" or "compress" for lower profiles.
    *   *Note*: It is easier to make a perfect system faster (optimization) than to make a fast, sloppy system perfect.

## 5. Summary
By decoupling Quality into a Profile:
*   **Scheduler** optimizes for Time.
*   **Simulation** optimizes for Math.
*   **Export** optimizes for Storage.

They all work together without tight coupling to deliver exactly what the user (or Agent) asked for.
