# 01 — Foundation Models (Apple Intelligence) Overview

## Why this is the primary lane
By early 2027, the most aggressive Apple-first approach is to treat the Foundation Models framework as the default LLM runtime:
- On-device by default (privacy + latency)
- Swift-native APIs
- Structured output / guided generation for reliable intent plans
- Tool calling for “press the buttons” integration

## What to build around
- Use a **structured Action Plan** as the source of truth (typed Swift model).
- Treat user-facing narration as secondary output that explains actions.
- Always implement runtime checks for model availability (Apple Intelligence can be disabled/unavailable).

## Source notes
- [research_notes/llm_model_research_2025-12-20/md/apple_foundation_models_on_device_llm_2025.md](research_notes/llm_model_research_2025-12-20/md/apple_foundation_models_on_device_llm_2025.md)
- [research_notes/llm_model_research_2025-12-20/md/macos_tahoe_26_foundation_models_requirements.md](research_notes/llm_model_research_2025-12-20/md/macos_tahoe_26_foundation_models_requirements.md)
