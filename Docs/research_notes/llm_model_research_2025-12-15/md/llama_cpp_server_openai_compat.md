# Search Results: ggerganov llama.cpp llama-server OpenAI compatible /v1/chat/completions

**Date:** 2025-12-15 23:52:54

## Answer

Here’s how to use llama.cpp’s llama-server with the OpenAI‑compatible /v1/chat/completions endpoint.

Quick start
- Start the server with a model and (optionally) an alias for the model id you’ll send in requests:
  - llama-server -m /path/to/model.gguf --port 8080 -a local
  - Basic UI: http://localhost:8080; Chat endpoint: http://localhost:8080/v1/chat/completions. ([github.com](https://github.com/ggml-org/llama.cpp))
- The server routes POST requests by the "model" field you send; using an alias is recommended. Autoloading can be controlled, and GET endpoints accept a model query parameter. ([raw.githubusercontent.com](https://raw.githubusercontent.com/ggml-org/llama.cpp/master/tools/server/README.md))

Minimal examples
- curl (non‑streaming):
  - curl http://localhost:8080/v1/chat/completions \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer no-key" \
    -d '{ "model": "local", "messages": [ {"role":"user","content":"Hello!"} ] }'
  The server supports both sync and streaming modes and aims to be OpenAI compatible. ([raw.githubusercontent.com](https://raw.githubusercontent.com/ggml-org/llama.cpp/master/tools/server/README.md))
- curl (streaming):
  - Add "stream": true to the JSON body. The stream ends with a [DONE] line, matching OpenAI’s SSE behavior. ([github.com](https://github.com/ggml-org/llama.cpp/issues/9291))
- Python (OpenAI SDK v1 style):
  - from openai import OpenAI
    client = OpenAI(base_url="http://localhost:8080/v1", api_key="sk-no-key-required")
    r = client.chat.completions.create(model="local", messages=[{"role":"user","content":"Hello!"}])
  Works as shown in the server README examples. ([raw.githubusercontent.com](https://raw.githubusercontent.com/ggml-org/llama.cpp/master/tools/server/README.md))

Supported features you may care about
- Tools / function calling: Send tools and tool_choice like OpenAI; start server with --jinja (and a compatible chat template if needed). parallel_tool_calls and tool parsing flags are available. See docs and examples in the server README. ([raw.githubusercontent.com](https://raw.githubusercontent.com/ggml-org/llama.cpp/master/tools/server/README.md))
- response_format: Supports {"type":"json_object"} and schema‑constrained JSON (including "json_schema"). ([raw.githubusercontent.com](https://raw.githubusercontent.com/ggml-org/llama.cpp/master/tools/server/README.md))
  - Note: there were reports of issues with response_format/json_schema in some Feb 2025 builds—upgrade to a recent build if you rely on this. ([github.com](https://github.com/ggml-org/llama.cpp/issues/11847?utm_source=openai))
- Multimodal: You can include images via image_url parts in messages if the model supports vision. ([raw.githubusercontent.com](https://raw.githubusercontent.com/ggml-org/llama.cpp/master/tools/server/README.md))
- Auth: If you start the server with --api-key or --api-key-file, endpoints will require and check the bearer token. Otherwise, any token is accepted. ([raw.githubusercontent.com](https://raw.githubusercontent.com/ggml-org/llama.cpp/master/tools/server/README.md))

What do you want next: a full request/response sample with tools, streaming client code, or help wiring this behind the OpenAI SDK/Node?
