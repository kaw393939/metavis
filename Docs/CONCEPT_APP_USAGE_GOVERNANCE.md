# Concept: App Usage Governance (Plans & Entitlements)

> **Goal**: Control application usage (Project Count, Project Types) via a licensing system powered by Unlock Codes.

## 1. The `UserPlan` (The Container)
While `ProjectLicense` controls a specific project, `UserPlan` controls the **Account**.

```swift
enum ProjectType: String, Codable {
    case basic     // Simple timeline
    case cinema    // Full ACEScg, multiple tracks
    case lab       // Scientific/Dev verification
    case commercial // Features for Ads
}

struct UserPlan {
    let tierName: String
    let maxProjectCount: Int
    let allowedProjectTypes: Set<ProjectType>
    let features: Set<FeatureFlag> // e.g. .cloudRendering, .collaboration
}
```

## 2. The `EntitlementManager`
A new component in `MetaVisKit` (or `MetaVisSession`) that acts as the Bouncer.

### Workflow: Creating a New Project
1.  **User**: Clicks "New Cinema Project".
2.  **Session**: Queries `EntitlementManager`.
    *   *Check 1*: `currentProjectCount < plan.maxProjectCount`?
    *   *Check 2*: `plan.allowedProjectTypes.contains(.cinema)`?
3.  **Result**:
    *   **Pass**: Project created.
    *   **Fail**: Agent intervenes. "You've reached your limit of 3 projects. Enter an unlock code to upgrade to Pro?"

## 3. The `UnlockCode` Mechanism
A cryptographic alphanumeric string (or file) that creates a customized build or upgrades an existing one.

*   **Offline Verification**: We use public/private key signing (Ed25519) so the app can verify codes without hitting a server (critical for on-set/air-gapped use).
*   **Capabilities**: A code can encode:
    *   `"LIMIT_PROJECTS=50"`
    *   `"UNLOCK_TYPE=CINEMA"`
    *   `"EXPIRY=2025-01-01"`

## 4. Custom Builds
Because the Governance is defined by the `UserPlan` configuration, we can easily generate custom builds for enterprise clients by simply baking a different `DefaultPlan` into the binary.
*   **MetaVis Free**: Max 3 Projects, Basic Type.
*   **MetaVis Pro**: Unlimited, Cinema Type.
*   **MetaVis Edu**: Unlimited, Lab Type, Watermarked.

## 5. Summary
*   **Governance Hierarchy**:
    *   **App Level**: `UserPlan` (How many projects? What types?)
    *   **Project Level**: `ProjectLicense` (What resolution? What export rights?)
*   **Business Model**: We sell the key to the gate. The engine is always perfect, but the user pays for the capacity to use it.
