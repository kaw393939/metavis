# Search Results: gemini-2.5-flash multimodal inputs images video audio JSON function calling

**Date:** 2025-12-15 23:53:47

## Answer

Here’s a concise cheat sheet for Gemini 2.5 Flash covering your keywords.

- What it is and I/O
  - Model code: gemini-2.5-flash (stable). Inputs: text, images, video, audio. Output: text only. Context: ~1,048,576 input tokens; up to 65,536 output tokens. Latest update: June 2025; knowledge cutoff: January 2025. ([ai.google.dev](https://ai.google.dev/gemini-api/docs/models?utm_source=openai))

- Multimodal inputs
  - Images/video/audio can be sent inline or via the Files API; YouTube URLs are also accepted for video. Supported video MIME types include mp4, mpeg, mov, avi, webm, etc. ([ai.google.dev](https://ai.google.dev/gemini-api/docs/video-understanding?utm_source=openai))
  - Audio specifics: ~32 tokens per second; up to ~9.5 hours total audio per request; downsampled for processing; multi-channel mixed to mono. ([ai.google.dev](https://ai.google.dev/gemini-api/docs/audio?utm_source=openai))
  - Media resolution control: use generation_config.media_resolution (LOW/MEDIUM/HIGH) to trade off cost vs. quality; 2.5 models have defined token budgets per level. ([ai.google.dev](https://ai.google.dev/gemini-api/docs/media-resolution))

- JSON/structured outputs
  - To force JSON, set response_mime_type=application/json and provide response_json_schema (JSON Schema). The model returns syntactically valid JSON matching your schema; streaming of partial JSON is supported. ([ai.google.dev](https://ai.google.dev/gemini-api/docs/structured-output))

- Function calling (tools)
  - Supported on 2.5 Flash. Define tools with function declarations (name, description, parameters schema). Modes: AUTO (default), ANY (force a call), NONE (disable). Parallel and compositional (multi-step) calls are supported. ([ai.google.dev](https://ai.google.dev/gemini-api/docs/models?utm_source=openai))

- Practical limits to remember
  - 2.5 Flash processes video and audio inputs but does not generate audio; output is text. For live voice I/O, use the Live API models; for TTS use a TTS-capable model. ([ai.google.dev](https://ai.google.dev/gemini-api/docs/models?utm_source=openai))

If you want, I can share a minimal Python or JavaScript snippet that:
- uploads an image/video/audio file,
- calls gemini-2.5-flash with function declarations, and
- returns a schema-validated JSON result.
