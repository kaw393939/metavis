# MetaVisCore

**MetaVisCore** is the foundational framework for the MetaVisKit engine. It contains the shared types, interfaces, and mathematical primitives used across the entire rendering pipeline.

## Features

- **Precision Time:** Rational number-based timekeeping for frame-perfect editing.
- **Safety & Governance:** Built-in types for managing AI privacy policies, user licensing, and watermarking.
- **Render Abstraction:** `RenderGraph` and `RenderNode` definitions for backend-agnostic rendering.
- **Device Protocol:** `VirtualDevice` interface for defining controllable entities.
- **Orchestration:** `FeedbackLoopOrchestrator` for managing iterative AI-driven workflows.
- **Color Science:** Reference implementations of ACEScg transforms and ASC CDL.

## Usage

### Time Handling
```swift
import MetaVisCore

// Precise explicit frame duration
let oneFrame = Time(Rational(1, 24))
```

### Governance
```swift
let plan = UserPlan.pro
if plan.allowedProjectTypes.contains(.cinema) {
    // Enable Cinema features
}
```

## Architecture

- **`Sources/MetaVisCore/Time.swift`**: The core `Time` struct.
- **`Sources/MetaVisCore/GovernanceTypes.swift`**: Licensing and Policy definitions.
- **`Sources/MetaVisCore/RenderGraph.swift`**: DAG definition for the render engine.

## Usage in System
This module should be imported by all other MetaVis modules (`MetaVisAudio`, `MetaVisGraphics`, etc) as the common language of data exchange.
