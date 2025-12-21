# LLM Model + Runtime Decision (MetaVis) — 2025-12-15

## Goal
Pick the **fastest, best** model stack for *planning* (strict JSON clip plans) with an explicit path to switch between **local** and **Gemini** under governance constraints.

This repo already has two integration shapes:
- **Local**: `Sources/MetaVisServices/LocalLLMService.swift` calls an **OpenAI-compatible** endpoint via `METAVIS_LLM_ENDPOINT`.
- **Gemini (cloud)**: `Sources/MetaVisServices/Gemini/*` + governance gates in `Sources/MetaVisCore/AIGovernance.swift` and optional multimodal QC in `Sources/MetaVisQC/GeminiQC.swift`.

## Summary recommendation
- **Default (fastest + governed)**: run a **local OpenAI-compatible server** and point `METAVIS_LLM_ENDPOINT` at it.
  - Runtime: **`llama.cpp` `llama-server`** (Metal) *or* **Ollama** (easiest).
  - Model (planning): **small instruct model (3B–8B) + low temp + strict JSON**.
- **Cloud (multimodal / expert review)**: keep **Gemini `gemini-2.5-flash`** for multimodal QA / “expert review” only when policy allows.
- **Apple on-device (long-term best local UX)**: evaluate Apple’s **Foundation Models** framework for an on-device model with **typed structured outputs** and tool calling (no network) when/if it fits your platform + entitlement constraints.

## Options matrix (what matters for MetaVis)
### A) Local text planner (what you need today)
Best fit: transcript → beats → JSON clip plan.
- **Pros**: lowest latency, no network governance burden, predictable operating cost, can run offline.
- **Cons**: you must choose/install a runtime + model; JSON reliability varies by model and needs constraints.

**Runtime choices**
- **`llama.cpp` `llama-server`**
  - Good: very fast on Apple Silicon, minimal overhead, OpenAI-style `/v1/chat/completions`.
  - Best when: you care about absolute latency and want a single-process server.
- **Ollama**
  - Good: easiest install + model management; OpenAI-compatible `/v1/chat/completions`; also supports tools and vision depending on model.
  - Tradeoff: slightly more overhead; “one more moving part”, but operationally simple.

**Model sizing (planning)**
- **3B–4B**: fastest; good enough if you constrain output and keep context small.
- **7B–8B**: slower but more reliable with longer context and fewer “formatting lapses”.

**How to make JSON reliable**
- Prefer servers that support `response_format` / JSON schema (“guided decode”) when possible.
- Otherwise: low temperature + strict “JSON only” prompts + one repair attempt (already implemented in `TranscriptEditPlanner`).

### B) Local multimodal (optional near-term)
Use when you want frame-aware planning/QC without cloud.
- Best practical approach today: **Ollama** (or llama.cpp vision) + a vision-language model.
- Reality: local multimodal is typically slower and more variable than cloud; keep evidence small (few downscaled keyframes).

### C) Gemini (cloud multimodal)
Best fit: “expert eye” validation of exports + occasional planning help.
- **Pros**: strong multimodal, huge context, supports JSON schema and tools; integrates cleanly with your existing `GeminiClient`.
- **Cons**: governance required; latency depends on network; costs.

Gemini docs note `gemini-2.5-flash` supports multimodal inputs and JSON schema via `response_mime_type=application/json` and `response_json_schema`.

### D) Apple Foundation Models (on-device)
Apple provides a Swift framework for on-device foundation model access with structured output and tool calling, plus an adapter story.
- **Pros**: best governance posture (on-device), likely strong latency UX, native typed structured outputs.
- **Cons**: OS/platform requirements and entitlements (especially for adapters); less portable.

## Governance alignment (already in-repo)
- Use `AIUsagePolicy` + `PrivacyPolicy` to decide **whether anything can leave device**.
- For planning, the safest cloud posture is **text-only** (no frames, no raw media) unless explicitly enabled.
- For multimodal QC, keep `mediaSource=.deliverablesOnly` and upload only derived evidence (keyframes, not raw).

## Evidence files (repro)
All `eai search` results are saved under:
- `research_notes/llm_model_research_2025-12-15/`
- Domain-filtered, source-bearing Markdown:
  - `research_notes/llm_model_research_2025-12-15/md/ollama_openai_compat.md`
  - `research_notes/llm_model_research_2025-12-15/md/llama_cpp_server_openai_compat.md`
  - `research_notes/llm_model_research_2025-12-15/md/gemini_flash_multimodal.md`
  - `research_notes/llm_model_research_2025-12-15/md/apple_on_device_llm_api.md`
  - `research_notes/llm_model_research_2025-12-15/md/governance_transcripts.md`

## Concrete “best now” pick (operational)
- **If you want the fastest planning today**: run `llama.cpp` `llama-server` + a **3B–7B instruct** model and point `METAVIS_LLM_ENDPOINT` at it.
- **If you want the easiest install today**: run **Ollama** and point `METAVIS_LLM_ENDPOINT` at `http://localhost:11434/v1/chat/completions`.
- Keep Gemini as a governed opt-in for multimodal QA.
