# LLM model research (2025-12-15)

This folder contains reproducible `eai search` outputs used for the model/runtime decision.

## How to reproduce
From repo root:

```zsh
mkdir -p research_notes/llm_model_research_2025-12-15

# JSON dumps
for q in \
  "fastest local llm macos metal apple silicon 2025 llama.cpp mlx ollama latency" \
  "best small instruct model for strict JSON output 2025 qwen2.5 llama phi" \
  "Gemini 2.5 flash multimodal latency function calling JSON mode 2025" \
  "Ollama OpenAI compatible v1 chat completions endpoint 2025" \
  "llama.cpp llama-server OpenAI compatible /v1/chat/completions 2025" \
  "MLX local LLM server OpenAI compatible 2025" \
  "LLaVA on macOS Ollama multimodal image input 2025" \
  "Moondream local vision language model macOS 2025" \
  "Apple Intelligence developer API on-device LLM access 2025" \
  "LLM governance sending transcripts to cloud PII redaction best practices 2025"; do \
  slug=$(echo "$q" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '_' | sed 's/^_//; s/_$//'); \
  eai search --json --show-sources "$q" > "research_notes/llm_model_research_2025-12-15/${slug}.json"; \
done

# Domain-filtered Markdown with sources
mkdir -p research_notes/llm_model_research_2025-12-15/md

eai search --show-sources -d ollama.com -d github.com \
  "Ollama OpenAI compatible v1 chat completions endpoint /v1/chat/completions" \
  -o research_notes/llm_model_research_2025-12-15/md/ollama_openai_compat.md

eai search --show-sources -d github.com \
  "ggerganov llama.cpp llama-server OpenAI compatible /v1/chat/completions" \
  -o research_notes/llm_model_research_2025-12-15/md/llama_cpp_server_openai_compat.md

eai search --show-sources -d ai.google.dev -d developers.google.com \
  "gemini-2.5-flash multimodal inputs images video audio JSON function calling" \
  -o research_notes/llm_model_research_2025-12-15/md/gemini_flash_multimodal.md

eai search --show-sources -d developer.apple.com \
  "Foundation Models framework on-device LLM API" \
  -o research_notes/llm_model_research_2025-12-15/md/apple_on_device_llm_api.md

eai search --show-sources -d nist.gov -d owasp.org -d cloud.google.com -d openai.com \
  "PII redaction best practices sending transcripts to LLM governance" \
  -o research_notes/llm_model_research_2025-12-15/md/governance_transcripts.md
```

## Output usage
- Decision writeup: `research_notes/LLM_MODEL_DECISION_2025-12-15.md`
- Raw evidence (JSON and Markdown) lives alongside this file.
