# Search Results: Google Vertex AI Veo 3 API generate video endpoint request response parameters duration resolution fps pricing quotas

**Date:** 2025-12-13 07:30:03

## Answer

Here’s a concise cheat sheet for Veo 3 on Vertex AI.

Models and endpoint
- Model IDs: veo-3.0-generate-001 (quality) and veo-3.0-fast-generate-001 (faster/cheaper). ([cloud.google.com](https://cloud.google.com/vertex-ai/generative-ai/docs/models/veo/3-0-generate-001?utm_source=openai))
- Generate video endpoint (long-running): POST https://us-central1-aiplatform.googleapis.com/v1/projects/PROJECT_ID/locations/us-central1/publishers/google/models/MODEL_ID:predictLongRunning. Poll status with …:fetchPredictOperation. ([docs.cloud.google.com](https://docs.cloud.google.com/vertex-ai/generative-ai/docs/model-reference/veo-video-generation))

Request shape (text-to-video)
- Body (essential fields):
  - instances[0].prompt: your text prompt.
  - parameters:
    - sampleCount: 1–4 outputs.
    - duration: 4, 6, or 8 (seconds). Default 8.
    - aspectRatio: "16:9" or "9:16".
    - resolution: "720p" or "1080p" (Veo 3 only; default 720p).
    - seed: optional uint32 for determinism.
    - storageUri: optional gs:// bucket to write results; otherwise bytes are returned.
    - negativePrompt: optional.
    - personGeneration: "allow_adult" (default), "dont_allow", or "allow_all" (allowlist). 
    - generateAudio: boolean; required for Veo 3 models if you want audio in the output. ([docs.cloud.google.com](https://docs.cloud.google.com/vertex-ai/generative-ai/docs/model-reference/veo-video-generation))

Response shape
- Initial response (submit): { "name": "projects/.../operations/OPERATION_ID" }.
- Polling response (fetchPredictOperation):
  - done: boolean
  - response: { "@type": "…GenerateVideoResponse", raiMediaFilteredCount, videos[] }
  - Each videos[i] has gcsUri and mimeType (video/mp4). If no storageUri was set, you get bytesBase64Encoded instead. ([docs.cloud.google.com](https://docs.cloud.google.com/vertex-ai/generative-ai/docs/model-reference/veo-video-generation))

Duration, resolution, fps
- Duration options: 4s, 6s, 8s (default 8). ([cloud.google.com](https://cloud.google.com/vertex-ai/generative-ai/docs/models/veo/3-0-generate-001?utm_source=openai))
- Aspect ratios: 16:9, 9:16. ([cloud.google.com](https://cloud.google.com/vertex-ai/generative-ai/docs/models/veo/3-0-generate-001?utm_source=openai))
- Resolutions: 720p or 1080p. ([cloud.google.com](https://cloud.google.com/vertex-ai/generative-ai/docs/models/veo/3-0-generate-001?utm_source=openai))
- Framerate: 24 fps. ([cloud.google.com](https://cloud.google.com/vertex-ai/generative-ai/docs/models/veo/3-0-generate-001?utm_source=openai))

Quotas and limits (Veo 3.0 generate / fast-generate)
- Requests per minute per project: 10.
- Max videos returned per request (sampleCount): up to 4.
- Video length per output: 4, 6, or 8 seconds. 
- Usage types: Fixed quota and Provisioned Throughput supported; Dynamic shared quota not supported. ([cloud.google.com](https://cloud.google.com/vertex-ai/generative-ai/docs/models/veo/3-0-generate-001?utm_source=openai))

Pricing (USD; as of December 2025)
- Veo 3 (quality):
  - Video + audio: $0.40 per second
  - Video only: $0.20 per second
- Veo 3 Fast:
  - Video + audio: $0.15 per second
  - Video only: $0.10 per second
- 720p and 1080p are included at the same per‑second rates on this page; check the SKUs page for your billing currency/region. ([cloud.google.com](https://cloud.google.com/vertex-ai/generative-ai/pricing?utm_source=openai))

Notes and tips
- Region: examples use us-central1; use the regional aiplatform endpoint that matches where you run Veo (us-central1 is the documented example). ([docs.cloud.google.com](https://docs.cloud.google.com/vertex-ai/generative-ai/docs/model-reference/veo-video-generation))
- If you omit storageUri, the completed operation returns base64 video bytes in response.videos[].bytesBase64Encoded; otherwise you’ll get GCS URIs. ([docs.cloud.google.com](https://docs.cloud.google.com/vertex-ai/generative-ai/docs/model-reference/veo-video-generation))

If you want, I can draft a ready-to-run curl request for your PROJECT_ID and preferred model/duration.
