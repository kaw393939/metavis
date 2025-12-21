# Concept: Quality Governance & Access Control

> **Goal**: Quality is not just a sliding scale of pixels; it is a **Licensed Utility**.
> The system must support "Quality Caps" to enable marketplace mechanics (e.g., Free Tier = 1080p, Pro Tier = 4K EXR).

## 1. The `ProjectLicense` (The Rules)
Every `Project` contains a `License` block that defines constraints.

```swift
struct ProjectLicense {
    let ownerId: UserID
    let maxResolution: Resolution    // e.g. 1920x1080
    let allowOpenEXR: Bool           // Only enabled for "Pro"
    let watermarkRequired: Bool      // Enforce watermarking?
}
```

## 2. The Enforcement Layer
Governance checks happen in `MetaVisSession` *before* the job reaches the Scheduler.

### Scenario: The Marketplace Sale
1.  **Creator** designs a complex "Sci-Fi Title Sequence".
2.  **Constraint**: They set `maxResolution = 720p` and `watermark = true` for the free sample.
3.  **Customer** downloads the project.
4.  **Action**: Customer tries to export 4K.
5.  **Refusal**:
    *   `Session` checks `ProjectLicense`.
    *   Detects `request.resolution (4K) > license.maxResolution (720p)`.
    *   **Agent Intervenes**: "This project is limited to 720p. Would you like to upgrade the license?"

## 3. Distributed "Graph" Impact
> "We need to consider how different quality settings will impact the other projects on the graph."

If Project B imports Project A:
*   Project A (Background) has a `License`.
*   Project B (Composition) inherits constraints?
*   **Resolution**: Ideally, Project B can render at 4K, but Project A's component will render at its capped resolution (fuzzy background) or with a watermark, *unless* B owns a license for A.
*   **The "Dependency Chain" check**: The final export quality is determined by the *lowest common denominator* of permissions in the graph.

## 4. User Identity ("The Default User")
We design for multi-tenant now, but implement simple.
*   **Architecture**: `User` struct with a `keychain`.
*   **Implementation (Phase 1)**: `User.default` (Admin access to everything).
*   **Implementation (Phase 2)**: `User.active` checks keys against Project UUIDs.

## 5. Automation & Overrides
*   **Sensible Automation**: The Agent defaults to the Max Allowed Quality.
*   **Overrides**: An Admin (or the Creator) can sign a temporary "Golden Ticket" to bypass restrictions for debugging or special renders.

## 6. Summary
We treat **Resolution and Fidelity as Assets**.
*   The Renderer is capable of "God Mode".
*   The **License** acts as a Governor valve.
*   This enables the business model without changing the rendering code.
