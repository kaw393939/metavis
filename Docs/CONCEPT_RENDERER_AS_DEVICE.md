# Concept: The Renderer as a Device

> **Question**: Should we treat the render as a device?
> **Answer**: **YES**.

## 1. The Paradigm Shift
If the Renderer is a `VirtualDevice`, it ceases to be a special "System Process" and becomes just another piece of **Virtual Hardware** in the rack.

### The `RenderDevice`
Just like a Camera has `iso` and `shutter`, the Renderer has:
*   **Properties** (State):
    *   `resolution`: "3840x2160"
    *   `colorSpace`: "ACEScg"
    *   `format`: "ProRes 4444"
*   **Actions** (Capabilities):
    *   `captureFrame(time: Time)`: Returns a still.
    *   `exportRange(start: Time, end: Time)`: Writes a file.

## 2. Why this is powerful

### A. Uniform Agent Interface
The Agent doesn't need a special "Render API". It uses the standard `Device` API.
*   *User*: "Export this at 1080p."
*   *Agent*:
    1.  Finds device type `.renderer`.
    2.  Checks `unsupported_resolutions` in `knowledgeBase`.
    3.  Calls `renderer.setProperty("resolution", "1080p")`.
    4.  Calls `renderer.perform("exportRange", ...)`

### B. "Intelligent" Rendering
Because it implements `DeviceKnowledgeBase`, the Renderer can teach.
*   *User*: "Why is my export huge?"
*   *Agent*: Queries `renderer.properties["format"].educationalContext`.
    *   *Result*: "ProRes 4444 preserves all color data but produces large files. Use HEVC for sharing."

### C. Swappable "Hardware"
We can have multiple Render Devices connected:
1.  **`QuickLookRenderer`**: Low quality, super fast (for UI preview).
2.  **`MasteringRenderer`**: Max quality, slow (for final delivery).
3.  **`CloudRenderer`**: Offload to a server farm.

## 3. Revised Architecture
The **Studio** contains:
1.  **Input Devices**: Cameras, Mics, LIGM.
2.  **Processor Devices**: **The Renderer**.
3.  **Output Devices**: Monitors, Speakers.

The **Job Queue** is effectively a playlist of commands sent to the `RenderDevice`.

## 4. Example Implementation
```swift
actor MetalRenderDevice: VirtualDevice {
    let name = "Titan Engine"
    var properties = [
        "resolution": .string("4K"),
        "oversample": .bool(true)
    ]
    
    let knowledgeBase = KnowledgeBase(
        description: "The main image processing unit.",
        tips: ["Disable oversampling for faster previews."]
    )
    
    func perform(action: "render", ...) { ... }
}
```
