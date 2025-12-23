# Search Results: Ollama OpenAI compatible v1 chat completions endpoint /v1/chat/completions

**Date:** 2025-12-15 23:51:55

## Answer

Here’s a quick cheat sheet for using Ollama’s OpenAI‑compatible Chat Completions endpoint.

What it is
- POST http://localhost:11434/v1/chat/completions (OpenAI schema, runs against your local Ollama models). API key is required by many clients but ignored by Ollama; set any value. ([docs.ollama.com](https://docs.ollama.com/api/openai-compatibility))

Minimal request
- Headers: Content-Type: application/json
- Body (example):
  {
    "model": "llama3.2",
    "messages": [
      {"role": "user", "content": "Hello!"}
    ]
  }
- curl: curl http://localhost:11434/v1/chat/completions -H "Content-Type: application/json" -d '{...}'. ([ollama.com](https://ollama.com/blog/openai-compatibility))

Using the OpenAI SDKs locally
- Python:
  base_url='http://localhost:11434/v1/', api_key='ollama'
  client.chat.completions.create(model='llama3.2', messages=[...])
- JS:
  new OpenAI({ baseURL: 'http://localhost:11434/v1', apiKey: 'ollama' })
  openai.chat.completions.create({ model: 'llama3.2', messages:[...] })
These follow the standard OpenAI client calls; only the base URL and dummy key differ. ([docs.ollama.com](https://docs.ollama.com/api/openai-compatibility))

Supported features and key fields
- Features: chat completions, streaming, JSON mode, reproducible outputs (seed), vision, tools (function calling), logprobs. ([docs.ollama.com](https://docs.ollama.com/api/openai-compatibility))
- Common fields: model, messages (text and images via image_url or base64 content parts), temperature, top_p, max_tokens, stop, seed, response_format, tools, tool_choice, stream, stream_options.include_usage, n, user, logit_bias. ([docs.ollama.com](https://docs.ollama.com/api/openai-compatibility))

Vision example
- Send messages content as an array with type:"text" and type:"image_url" (or base64). Works via the same /v1/chat/completions call. ([docs.ollama.com](https://docs.ollama.com/api/openai-compatibility))

Model name tips
- You can alias default OpenAI model names for compatibility (e.g., map llama3.2 to “gpt-3.5-turbo”): ollama cp llama3.2 gpt-3.5-turbo, then use "model": "gpt-3.5-turbo". ([docs.ollama.com](https://docs.ollama.com/api/openai-compatibility))

Context size
- OpenAI’s API doesn’t expose context-size controls. To change it in Ollama, create a Modelfile with PARAMETER num_ctx and build a new model, then call it via /v1/chat/completions. ([docs.ollama.com](https://docs.ollama.com/api/openai-compatibility))

Notes and caveats (compatibility)
- Some streaming details differ from OpenAI today (e.g., role repeated per chunk, missing tool_calls[].index in streamed chunks). If your client relies on strict streaming semantics, account for these differences. ([github.com](https://github.com/ollama/ollama/issues/7626?utm_source=openai))

Also available
- Ollama additionally supports /v1/responses (non‑stateful flavor) if you prefer the newer OpenAI Responses API. ([docs.ollama.com](https://docs.ollama.com/api/openai-compatibility))

If you want, I can provide ready‑to‑paste examples for streaming, tool calls, or image inputs.
