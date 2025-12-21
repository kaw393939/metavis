# Concept: Intelligent Devices & The "Empowerment" Standard

> **Philosophy**: "Give them a fish, they eat for a day. Teach them to fish, they create cinema." 
> The Agent is a **Co-Pilot**, not just an Autopilot.

## 1. The Core Problem
We have powerful hardware (iPhone Lidar, Mac Media Engine), but users don't know *how* to use them effectively.
*   **Current State**: A "Record" button.
*   **Desired State**: An Agent that says, "I see you're shooting in low light. Switching to 24fps will give you more exposure. Shall I do that?"

## 2. The Solution: Self-Documenting Devices
We must standardize `VirtualDevice` so that **Documentation is Code**. You cannot compile a device without explaining it.

### The `CapabilityManifest` (The Standard)
Every `VirtualDevice` must expose a rich manifest, not just a list of functions.

```swift
struct ActionManifest {
    let name: String            // "iso"
    let technicalType: String   // "Float"
    
    // The "Help System" Hooks
    let humanDescription: String // "Sensor Sensitivity"
    let educationalContext: String // "Higher ISO brightens the image but adds grain (noise)."
    let bestPractices: [String]  // ["Keep under 800 for clean look", "Use 3200 for gritty style"]
    
    // Agent Hints
    let safetyLevel: SafetyLevel // .safe, .expert_only
}
```

## 3. The "Ask The Expert" Loop
The Agent uses this manifest to triage requests.

1.  **User**: "It's too dark."
2.  **Agent (Internal)**: Queries `CameraDevice.capabilities`.
    *   Finds `iso`, `shutterAngle`, `aperture`.
    *   Reads `educationalContext`: "ISO brightens...", "Shutter slows..."
3.  **Agent (Action)**: "I can bump the ISO to 1600, but it might get grainy. Or we can slow the shutter?"
4.  **User**: "Let's risk the grain."
5.  **Agent**: Calls `device.perform("iso", 1600)`.

## 4. Enforcement Strategy
To ensure this isn't skipped by lazy developers (us):

### A. The "Capability Protocol"
The `VirtualDevice` protocol will mandate a `knowledgeBase` property.
```swift
protocol VirtualDevice {
    var knowlegeBase: DeviceKnowledgeBase { get } // Compiler error if missing!
}
```

### B. The "Schoolteacher" Test
A standard unit test in `MetaVisCoreTests` that iterates *all* registered devices and fails if:
*   Description is empty.
*   Description is too short (< 10 words).
*   No "Best Practices" provided.

## 5. Architectural Impact
*   **UI Simplicity**: The native UI can be minimal (just the view). The controls are surfaced via the Agent Chat.
*   **Validation**: When we send data to Gemini ("Ask the Expert"), we send this Manifest too, so Gemini knows exactly what the hardware *can* do.
