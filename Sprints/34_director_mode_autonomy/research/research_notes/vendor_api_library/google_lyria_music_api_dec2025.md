# Search Results: Google Vertex AI Lyria API music generation endpoint request response parameters duration seed lyrics

**Date:** 2025-12-13 07:30:58

## Answer

Here’s the quick reference for Google Vertex AI’s Lyria (lyria-002) music generation API.

Endpoint
- POST https://LOCATION-aiplatform.googleapis.com/v1/projects/PROJECT_ID/locations/LOCATION/publishers/google/models/lyria-002:predict. ([cloud.google.com](https://cloud.google.com/vertex-ai/generative-ai/docs/model-reference/lyria-music-generation?utm_source=openai))

Request (fields and rules)
- instances[0].prompt (string, required): US‑English text describing the music to generate.
- instances[0].negative_prompt (string, optional): things to avoid (e.g., “vocals, dissonant”).
- instances[0].seed (integer, optional): reproducible output; cannot be used with sample_count in the same request.
- parameters.sample_count (integer, optional): number of clips to return; cannot be used with seed in the same request. Max clips per request is up to 4. ([cloud.google.com](https://cloud.google.com/vertex-ai/generative-ai/docs/model-reference/lyria-music-generation?utm_source=openai))

Response (shape)
- predictions: array of objects, one per generated clip:
  - audioContent: base64-encoded WAV
  - mimeType: "audio/wav"
- model, deployedModelId: metadata. ([cloud.google.com](https://cloud.google.com/vertex-ai/generative-ai/docs/music/generate-music?utm_source=openai))

Duration
- Fixed length; you can’t set duration in the request. Each returned clip is ~32.8 seconds at 48 kHz. ([cloud.google.com](https://cloud.google.com/vertex-ai/generative-ai/docs/music/generate-music?utm_source=openai))

Seed
- Integer for deterministic generation with the same prompt/params. Mutually exclusive with parameters.sample_count. ([cloud.google.com](https://cloud.google.com/vertex-ai/generative-ai/docs/model-reference/lyria-music-generation?utm_source=openai))

Lyrics / vocals
- Not supported. The public Lyria API on Vertex AI is text‑to‑music for instrumental audio only; it doesn’t take lyrics or generate singing voices. Prompts must be in US English. ([cloud.google.com](https://cloud.google.com/vertex-ai/generative-ai/docs/music/generate-music?utm_source=openai))

Minimal JSON example
- Request body:
  - instances: [{ "prompt": "Uplifting orchestral piece with soaring strings and triumphant brass", "negative_prompt": "dissonant, vocals", "seed": 12345 }]
  - parameters: {}

- Response (predictions[0]):
  - { "audioContent": "BASE64_WAV...", "mimeType": "audio/wav" } ([cloud.google.com](https://cloud.google.com/vertex-ai/generative-ai/docs/model-reference/lyria-music-generation?utm_source=openai))

Want a ready-to-run curl or Python snippet with base64 decoding to a .wav file?
