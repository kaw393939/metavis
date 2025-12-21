# 02 — Adapters: Lifecycle + Training (Apple-first)

## What adapters are for
Adapters specialize the system on-device model for MetaVis:
- Intent/tool-call accuracy ("press the buttons")
- Cinematic editor voice (user-facing explanations)
- Domain vocabulary and safe defaults

## Lifecycle (production)
1. Train adapter(s) against a specific system model version.
2. Export `.fmadapter`.
3. Host adapters on your server.
4. Deliver to the app via Background Assets (large asset packs).
5. Select compatible adapter at runtime based on system model version.
6. Observe quality regressions and retrain when the system model updates.

## Practical constraints to plan for
- Shipping adapters requires an entitlement (Account Holder request).
- Adapters are tied to a specific system model version.
- Training may require more resources than a 16GB dev laptop; plan a dedicated training machine/worker.

## Source notes
- [research_notes/llm_model_research_2025-12-20/md/apple_foundation_models_adapters_training_toolkit_2025_2026.md](research_notes/llm_model_research_2025-12-20/md/apple_foundation_models_adapters_training_toolkit_2025_2026.md)
- [research_notes/llm_model_research_2025-12-20/md/foundation_models_entitlements_adapter_distribution.md](research_notes/llm_model_research_2025-12-20/md/foundation_models_entitlements_adapter_distribution.md)
