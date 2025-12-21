# Awaiting Implementation

## Gaps & Missing Features
- **Identity (true re-ID)**: No faceprints / cross-shot re-identification yet. Current `personId` is an MVP derived from deterministic track indices.
- **Multi-person validation (real assets, no mocks)**: Need a 2+ person fixture and E2E tests to verify track stability, churn handling, and eventual re-ID.
- **Bites (integration)**: Bite map can be derived deterministically from sensors, but is not yet wired into a CLI/export artifact pipeline.

## Technical Debt
- **Stubbed Services**: Any planned `FaceIdentityService` faceprint path still needs a real implementation.

## Recommendations
- Add a real multi-person fixture and extend E2E tests (no mocks).
- Implement faceprint-backed identity/re-ID when a stable API choice is available.
- Decide where `bites.v1.json` is emitted (CLI vs export pipeline) and add an E2E test around that artifact.
