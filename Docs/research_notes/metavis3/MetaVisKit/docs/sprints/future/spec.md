# MetaVisKit - Specification

## Goals
1.  Provide a unified, high-level API for macOS, iOS, and visionOS apps.
2.  Orchestrate the lower-level modules (`Simulation`, `Timeline`, `Perception`).

## Requirements
-   **Platform Agnostic**: Must work on all Apple platforms.
-   **SwiftUI Integration**: Provide `MetaVisView` (macOS/iOS) and `MetaVisVolume` (visionOS).
-   **Async/Await**: All long-running operations (render, analyze) must be async.
