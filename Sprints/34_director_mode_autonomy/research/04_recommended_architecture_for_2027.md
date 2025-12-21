# 04 — Recommended Architecture for 2027 (Director Mode)

## Primary loop
1. Detect stable timeline state (CRDT/timeline idle window).
2. Build a bounded context payload (selection, transcript excerpt, constraints).
3. Request a typed Action Plan from Foundation Models.
4. Validate each action (schema + invariants + safety checks).
5. Execute actions (tier-dependent: suggest/confirm/auto).
6. Run `DeliverableVerifier` and record trace.

## Action Plan contract (shape)
- `actions[]`: executable tool calls/intents
- `message`: cinematic explanation
- `needsClarification`: question when required inputs are missing

## Supporting lanes (not primary)
Core ML Tools + MLX + llama.cpp are useful for:
- dev tooling
- performance experiments
- CI environments without Apple Intelligence

## Source notes
- Foundation Models requirements: [research_notes/llm_model_research_2025-12-20/md/macos_tahoe_26_foundation_models_requirements.md](research_notes/llm_model_research_2025-12-20/md/macos_tahoe_26_foundation_models_requirements.md)
- On-device model design notes: [research_notes/llm_model_research_2025-12-20/md/apple_on_device_foundation_model_3b_2bit_qat_2025.md](research_notes/llm_model_research_2025-12-20/md/apple_on_device_foundation_model_3b_2bit_qat_2025.md)
- Core ML LLM support (state + compression):
  - [research_notes/llm_model_research_2025-12-20/md/coremltools_stateful_llm_kv_cache_2025.md](research_notes/llm_model_research_2025-12-20/md/coremltools_stateful_llm_kv_cache_2025.md)
  - [research_notes/llm_model_research_2025-12-20/md/coremltools_weight_compression_llm_2025.md](research_notes/llm_model_research_2025-12-20/md/coremltools_weight_compression_llm_2025.md)
