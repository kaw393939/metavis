# MetaVisTimeline - Legacy Code References

This document tracks the sequencing and editing logic.

## Timeline Model
*   **`metavis_render/Sources/MetaVisRender/Timeline/`**
    *   **Description**: The NLE core.
    *   **Key Features**:
        *   `AnimationCurve.swift`: Bezier curve interpolation.
        *   `Keyframe.swift`: Time-value pairs.
        *   `TimelineToGraphConverter.swift`: Converts the linear timeline into a render graph.

## Graph Logic
*   **`metavis_render/Sources/MetaVisRender/Timeline/Graph/`**
    *   **Description**: Node-based representation of the timeline.
