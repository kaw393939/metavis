# MetaVisCore Assessment

## Initial Assessment
MetaVisCore serves as the foundational library for the MetaVis system, providing essential data types, governance structures, and orchestration logic. It does not contain rendering logic itself but defines the *schema* and *rules* for the system.

## Capabilities

### 1. High-Precision Time System
- **`Time.swift`**: Implements a `Rational` number system with a tick scale of 1/60000s.
- **Why**: Ensures frame-accurate timing without floating-point drift, essential for video editing and deterministic auditing.
- **Features**: `Time` struct, `TimeRange`, arithmetic operators, and fast-path for fixed ticks.

### 2. Comprehensive Governance System
- **`QualityPolicyBundle.swift`**: Aggregates all policy types into a single bundle.
- **Policies**:
    - `VideoContainerPolicy`: Resolution, frame rate, duration limits.
    - `VideoContentPolicy`: Content checks (luma stats, temporal variety).
    - `DeterministicQCPolicy`: Audio/Video presence and peaks.
    - `AIGatePolicy`: Narrative and keyframe requirements.
    - `AIUsagePolicy` & `PrivacyPolicy`: Controls data egress (deliverables vs raw, redaction).
- **Impact**: Allows the system to rigidly enforce quality and privacy standards at the type level.

### 3. Feedback Loop Orchestration
- **`FeedbackLoopOrchestrator.swift`**: A generic, type-safe engine for running iterative loops.
- **Flow**: Proposal -> Evidence -> QA -> (Escalation) -> Decision -> Edit -> Loop.
- **Design**: Heavily file-system based (writes artifacts per cycle), promoting transparency and auditability.

### 4. Render Structures
- **`RenderGraph.swift`**: Defines `RenderNode` and `RenderGraph` as a Directed Acyclic Graph (DAG).
- **Role**: Pure data structure; separates graph definition from execution.
- **`RenderRequest.swift`**: Encapsulates a request to render a specific graph at a specific time/resolution.

## Technical Gaps & Debt

### 1. Mixed Responsibilities
The module mixes "low-level types" (`Time`, `Rational`, `StableHash`) with "high-level logic" (`FeedbackLoopOrchestrator`, `Governance`).
- **Risk**: Changes to governance logic might trigger recompilation of anything depending on `Time`.

### 2. File System Dependency
`FeedbackLoopOrchestrator` is tightly coupled to `FileManager` and writing JSON artifacts to disk.
- **Gap**: Difficult to run in-memory capability or strictly unit test without disk I/O.
- **Improvement**: Abstract storage backend.

### 3. Foundation Reliance
Heavy use of `Foundation` (e.g., `UUID`, `URL`, `FileManager`).
- **Optimization**: Minimal impact for now, but could limit portability to non-Apple platforms if that ever becomes a goal (unlikely for this project).

## Improvements

1.  **Split Module**: Consider extracting `Time` and primitive types into a `MetaVisPrimitives` module to reduce recompilation frequency.
2.  **Swift `Duration`**: Investigate if Swift's native `Duration` type (iOS 16+) can replace or augment the custom `Time` struct.
3.  **Graph Validation**: `RenderGraph` exists but `MetaVisCore` doesn't seem to validate it (cycles, disconnected nodes). Add a validator in this layer.
