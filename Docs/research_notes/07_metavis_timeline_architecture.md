# Research Note: MetaVisTimeline Architecture

**Source Documents:**
- `MetaVisTimeline/Timeline.swift`, `Track.swift`, `Clip.swift`
- `MetaVisTimeline/TimelineGraphBuilder.swift`
- `MetaVisTimeline/Keyframe.swift`

## 1. Executive Summary
`MetaVisTimeline` is a production-ready **NLE Data Model**. It is fully decoupled from the rendering engine, acting as the "Creative Description" that sits between the User/Agent and the Render Engine.

**Verdict:** This package can be adopted **as-is** for MetaVisKit2. It provides exactly the architecture needed for the "Stateful Application Model" identified in the previous research phase.

## 2. Core Data Structures
### A. The Hierarchy
-   **`Timeline`**: Root container. Calculates total duration dynamically.
-   **`Track`**: Ordered list of clips.
    -   *Logic:* Enforces non-overlapping clips via binary search insertion.
    -   *Types:* Generic, Video, Audio.
-   **`Clip`**: The atomic unit.
    -   *Dual Timing:* `range` (Timeline Time) vs `sourceRange` (Media Time). This enables **Slip** and **Slide** edits out of the box.
    -   *Status:* `synced`, `offline` (Matches existing asset logic).

## 3. The Compilation Layer (`TimelineGraphBuilder`)
This is the bridge between the "NLE View" and the "Render Graph".
-   **Function:** `build(from: Segment) -> NodeGraph`
-   **Strategy:** It converts a vertical slice of the timeline (at a specific time) into a compositing graph.
-   **Modes:**
    -   **`Sequence`**: Standard A/B Roll editing. Handles Cuts and Transitions (`Dissolve`, `Wipe`).
    -   **`Stack`**: Compositing mode. Additive blends (e.g. valid for JWST stacking).

## 4. Animation System
A robust Keyframe engine is included.
-   **Generics:** `Keyframe<T: Interpolatable>`. Animated Properties can be Float, Double, Point, Color (`SIMD4`).
-   **Interpolation:** Linear, Step, Bezier (Cubic Hermite).
-   **Easing:** Full implementation of Penner equations (`easeOutElastic`, `easeInQuad`).
-   **Extrapolation:** `PingPong` and `Loop` support for seamless cycling.

## 5. Synthesis for MetaVisKit2
-   **Adoption:** We will use `MetaVisTimeline` as the backing store for the new `ProjectSession`.
-   **Integration:**
    -   User/Agent edits the `Timeline` struct directly (via the new `EditIntent` API).
    -   The `TimelineGraphBuilder` will be moved to `MetaVisKit2` logic to act as the "JIT Compiler" for the Render Engine.
