# System Critique: MetaVisKit2

> **Objective**: Ruthlessly analyze the proposed architecture for weakness, over-engineering, and friction.

## 1. The Device Abstraction (`VirtualDevice`)
**Critique**: Is everything *really* a device?
*   **Risk**: Treating a "Color Corrector" as a "Device" with `perform(action: "setGamma")` is heavy. It introduces String-based lookups (`perform("gamma")` vs `corrector.gamma = 2.2`) and async Actor hopping for operations that should be instant 60fps adjustments.
*   **Verdict**: **Over-Engineered for Real-Time**.
*   **Fix**: Reserve `VirtualDevice` for *Stateful Hardware* (Cameras, Renderers, Generators). Use standard Swift Structs/Protocol functions for *Signal Processing* (Color Correction, Filters) inside the high-performance loop. "Don't send a letter to change a lightbulb."

## 2. The Governance Layer (`UserPlan`, `ProjectLicense`)
**Critique**: The "Double Gate".
*   **Risk**: Having two layers of permission (App Level + Project Level) creates a "Matrix of Rejection."
    *   User has `Pro App` but downloads `Limited Project`. -> Conflict.
    *   User has `Free App` but opens `Pro Project` (sent by friend). -> Conflict.
*   **Friction**: If the Agent interrupts every 5 minutes with "Upgrade to Pro to render this PBR Shadow", users will quit.
*   **Verdict**: **High Friction Risk**.
*   **Fix**:
    *   **Graceful Degradation**: Instead of blocking, *downgrade*. If I open a Pro project on a Free app, just disable the Pro features (e.g., disable 4K, render at 1080p) silently with a "Preview Mode" banner. Don't stop the fun.

## 3. The "Signal Path" Metaphor
**Critique**: Universal Signals.
*   **Risk**: Mixing Audio, Video, and Control into one "Signal" concept is theoretically beautiful but practically messy. Audio is 48kHz (samples), Video is 24Hz (frames). Syncing them in a unified "consume(signal)" loop often leads to audio glitches or video stutter.
*   **Verdict**: **Implementation Danger Zone**.
*   **Fix**: Keep the *Timeline* unified, but split the *Engine* pipelines early. Audio Engine runs on its own high-priority thread. Video Engine runs on the GPU. They sync only at the "Playhead" clock, never byte-for-byte.

## 4. Agent Dependency
**Critique**: "The Agent will explain it."
*   **Risk**: We are using the Agent as a crutch for bad UI. If a feature needs an AI explanation, maybe the feature is too complex? Relying on an LLM for basic tooltips is slow and expensive (latency).
*   **Verdict**: **Lazy UX Trap**.
*   **Fix**: The `knowledgeBase` is good, but the UI must be usable *without* the Agent. The Agent should be for *Strategy* ("How do I make this scary?"), not *Operations* ("How do I change ISO?").

## 5. Summary Scorecard
*   **Architecture**: A- (Solid modularity).
*   **Performance**: B- (Risk of Actor overhead in render loop).
*   **UX / Fun**: B (Governance could kill the vibe).
*   **Maintainability**: A (Clean separation).
