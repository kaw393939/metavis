# 03 — iPhone Availability + Capability Tiering

Even with aggressive OS targets, Foundation Models availability is not guaranteed at runtime (Apple Intelligence can be off, device not eligible, locale unsupported, etc.). Director Mode must degrade gracefully.

## Proposed capability tiers
- Tier A: Foundation Models available → full Action Plan + tool execution + narration
- Tier B: Model unavailable → reduced assistance (suggestions / explain-only / confirm-first only)

## Required behavior
- Always check model availability before enabling Director Mode.
- Keep the same user-visible workflow where possible; only reduce autonomy.

## Source notes
- [research_notes/llm_model_research_2025-12-20/md/ios18_iphone16_foundation_models_availability.md](research_notes/llm_model_research_2025-12-20/md/ios18_iphone16_foundation_models_availability.md)
