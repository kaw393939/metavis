# Search Results: MLX LM mlx-lm serve OpenAI compatible server 2025

**Date:** 2025-12-20 17:03:24

## Answer

Here’s the quick way to run MLX LM’s OpenAI‑compatible server in 2025 and call it from an OpenAI client.

1) Install
- pip install mlx-lm openai  (macOS on Apple Silicon; MLX docs list system requirements and alternatives) ([github.com](https://github.com/ml-explore/mlx-lm))

2) Start the server
- Basic: mlx_lm.server
- Customize host/port/log level (example): mlx_lm.server --host 0.0.0.0 --port 8585 --log-level DEBUG ([gist.github.com](https://gist.github.com/awni/bcd59f342d5be8a9d6b4268d0c782d25?utm_source=openai))

3) Call it with the OpenAI client (Chat Completions)
- Python:
  from openai import OpenAI
  client = OpenAI(base_url="http://localhost:8080/v1", api_key="not-needed")
  resp = client.chat.completions.create(
      model="mlx-community/qwen3-4b-4bit-DWQ",
      messages=[{"role":"user","content":"Hello from MLX LM!"}],
  )
  print(resp.choices[0].message.content)
  This is the official example pattern for mlx_lm.server + OpenAI client. ([gist.github.com](https://gist.github.com/awni/bcd59f342d5be8a9d6b4268d0c782d25?utm_source=openai))

4) Quick curl test
- curl http://localhost:8080/v1/chat/completions -H "Content-Type: application/json" -d '{"model":"mlx-community/qwen3-4b-4bit-DWQ","messages":[{"role":"user","content":"Hi!"}]}' 
  (Use your preferred MLX‑compatible model repo id.) ([gist.github.com](https://gist.github.com/awni/bcd59f342d5be8a9d6b4268d0c782d25?utm_source=openai))

Notes
- Install command and general usage for mlx-lm are in the official repo; MLX itself documents current platform requirements. ([github.com](https://github.com/ml-explore/mlx-lm))
- The server exposes OpenAI‑compatible endpoints (e.g., /v1/chat/completions). You can override host/port as shown above. ([gist.github.com](https://gist.github.com/awni/bcd59f342d5be8a9d6b4268d0c782d25?utm_source=openai))
- Not for production: maintainers caution that mlx_lm.server implements only basic security checks. For more features/hardening, consider community servers that wrap MLX with OpenAI‑compatible APIs:
  - cubist38/mlx-openai-server (FastAPI; chat, multimodal, embeddings, function calling) ([github.com](https://github.com/cubist38/mlx-openai-server?utm_source=openai))
  - madroidmaq/mlx-omni-server (OpenAI + Anthropic‑compatible; local inference suite) ([github.com](https://github.com/madroidmaq/mlx-omni-server?utm_source=openai))
  - nath1295/MLX-Textgen (OpenAI endpoints with prompt caching) ([github.com](https://github.com/nath1295/MLX-Textgen?utm_source=openai))
  Production warning reference: “mlx_lm.server is not recommended for production…” issue. ([github.com](https://github.com/ml-explore/mlx-examples/issues/1310))

Want me to tailor the command for a specific model (e.g., Llama 3.2 Instruct) or show a streaming example?
