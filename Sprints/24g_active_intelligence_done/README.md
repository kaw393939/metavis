# Sprint 24g: Active Intelligence

**Focus:** Replacing the "Cardboard Steering Wheel".

This sprint brings the actual Machine Learning capabilities online. Up until now, the system has pretended to be smart using regex and hardcoded rules. In this sprint, we integrate real inference engines (CoreML and Vertex AI) to make the "AI Editor" assumption a reality.

## Contents
*   [Specification](spec.md)
*   [Architecture](architecture.md)
*   [TDD Plan](tdd_plan.md)
*   **Artifacts:** `MetaVisServices`, `MetaVisSession` reviews.

## Primary Deliverables
1.  **Robust LLM Abstraction** (Protocol-based, swappable).
2.  **Multimodal Device Support** (Images in Gemini).
3.  **Responsive Session** (Request cancellation).
4.  **Secure Config** (No hardcoded backdoors).

## Status (2025-12-22)
- LLM abstraction + deterministic test provider: implemented.
- Gemini multimodal: implemented via `ask_expert` supporting optional `imageData` + `imageMimeType`.
- Session cancellation + deterministic throttling: implemented.
- Secure config hardening: entitlement unlock backdoor removed; unlock now requires an injected verifier.
- Gemini API rate limiting: implemented via optional token bucket (env-configured).
