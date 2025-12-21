# MetaVisKit2 TDD Strategy

## 1. Core Philosophy: "Testable by Design"
We are not just writing tests; we are designing the system to be verifiable. The legacy system failed because tight coupling made isolation impossible.

**The Golden Rule:**
> No implementation code is written until a failing test (or at least a defined Protocol + Mock) exists.

## 2. The Testing Pyramid

### Level 1: Unit Tests (70%)
*   **Target**: Pure functions, Data Models, ViewModels, State Reducers.
*   **Requirement**: Must run in < 10ms.
*   **Technique**:
    *   **Input/Output**: Verify `f(state, action) -> new_state`.
    *   **No IO**: Filesystem, Network, and GPU are **BANNED**.
    *   **Mocks**: Use `TestDouble` implementations for all dependencies.

### Level 2: Integration Tests (20%)
*   **Target**: Interaction between Actors (e.g., `Session` talking to `Scheduler`).
*   **Requirement**: Must run in < 1s.
*   **Technique**:
    *   **In-Memory DB**: Use SQLite in `.memory` mode for `MetaVisScheduler`.
    *   **Mock GPU**: Use a `HeadlessSimulation` driver that returns black frames without touching Metal.

### 2.1 Contract Tests for Evidence & Scene State (Core Feature)
MetaVis relies on deterministic sidecars and derived summaries. These must be treated as first-class contracts.

*   **Evidence Pack contract**: file formats and fields are stable (versioned) and deterministic.
*   **Scene State contract**: derived interval outputs are stable and explainable (reason codes).
*   **Golden fixtures**: small, curated media assets used to lock behaviors.

Related contract: `Docs/specs/SCENE_STATE_DATA_DICTIONARY.md`.

### Level 3: Snapshot Tests (5%)
*   **Target**: SwiftUI Views (`EditorView`), Render Output (`SimulationEngine`).
*   **Technique**:
    *   **Views**: Render View to Image -> Compare with Reference.
    *   **Frames**: Render Frame -> Compare Hash/Histogram with Reference (Tolerance < 0.1%).

### Level 4: UI/E2E Tests (5%)
*   **Target**: Major User Flows (Import -> Edit -> Export).
*   **Technique**: automation via `XCUITest`.

## 3. Implementation Rules

### 3.1 Protocol-First Design
Every major component MUST be defined by a Protocol *before* the Class/Actor is created.

**Incorrect:**
```swift
class AudioEngine { ... }
```

**Correct:**
```swift
protocol AudioEngineProtocol: Sendable {
    func play() async throws
}

// The Real Implementation (Integration/Prod)
actor AudioEngine: AudioEngineProtocol { ... }

// The Test Mock (Unit Tests)
actor MockAudioEngine: AudioEngineProtocol { ... }
```

### 3.2 Dependency Injection
Dependencies must be injected at `init`. Singletons (`.shared`) are **FORBIDDEN** in logic classes.

**Correct:**
```swift
init(
    audio: AudioEngineProtocol,
    scheduler: SchedulerProtocol
)
```

### 3.3 The "Humble Object" Pattern
Isolate complex, hard-to-test logic (Metal, AVFoundation) into thin wrappers that are easy to mock. The logic that *uses* them should be pure.

*   **Hard to Test**: `AVAssetReader` (Filesystem, Async).
*   **Testable**: `FrameDecoderProtocol`.
*   **Strategy**: Create a `Hero` (Business Logic) that talks to a `Humble` (Thin Wrapper). Test the `Hero` extensively using a Mock Wrapper.

## 4. TDD Workflow
1.  **Red**: Create a `XCTestCase`. Define the expected behavior. Assert fail.
2.  **Green**: Write the *minimum* code to pass.
3.  **Refactor**: Clean up.
4.  **Protocolize**: Extract Protocol if not done already.
5.  **Mock**: Update Mocks for other consumers.

## 5. Tooling
*   **Framework**: XCTest (Native).
*   **Mocks**: Manual Mocks (Swift Macros for Autosynthesis if available, else hand-rolled).
*   **CI**: GitHub Actions (Running `swift test`).

## 6. Performance & Device Test Gating
Some tests require real video decode, Vision, Metal, or longer-running workloads.

Rules:
- Heavy tests must be opt-in (env var gated) so default `swift test` stays fast.
- Performance tests must be deterministic and budgeted (explicit thresholds).
- Render integration tests should assert contract-level properties ("output differs", histograms, hashes) rather than brittle pixel-perfect comparisons.
