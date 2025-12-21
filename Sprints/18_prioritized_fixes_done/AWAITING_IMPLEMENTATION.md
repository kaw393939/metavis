# Awaiting Implementation: Remediation Plan

## Priority 0: Critical Integrity Fixes (The "Milk Crates")
- Implement a true “linked selection” model (optional): ripple delete currently shifts downstream clips across all tracks, but does not remove linked audio clips as a paired delete.
- Project persistence beyond recipes: if a longer-lived `ProjectContext`/workspace format is required (beyond loading a recipe JSON), define schema + migration strategy.

## Priority 1: Enabling the Vision (The "Corvette")
- **Identity Service**: `FaceIdentityService` is a stub. Implement `VNGenerateFacePlatformFeaturesRequest` for real person re-id.
- **Audio Dynamics**: `AudioMasteringChain` has no compression. Re-implement dynamics using `AVAudioUnitDistortion` (limiter) or custom DSP.
- **Governance**: Privacy/redaction is already applied in `GeminiPromptBuilder`; extend coverage/tests if policy enforcement needs hard guarantees.
