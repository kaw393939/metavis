# Search Results: Gemini API generateContent inlineData fileData uploadFile supported mime types image/jpeg image/png video/mp4 video/quicktime size limits

**Date:** 2025-12-13 07:27:56

## Answer

Here’s the quick cheat‑sheet for Gemini API media in generateContent.

Inline data (parts.inlineData / Blob.data)
- Supported types (common): images image/jpeg, image/png; video video/mp4, video/quicktime (aka video/mov). Full image list also includes image/webp, image/heic, image/heif; full video list includes video/mpeg, video/avi, video/x-flv, video/mpg, video/webm, video/wmv, video/3gpp. ([ai.google.dev](https://ai.google.dev/gemini-api/docs/vision?utm_source=openai))
- Size limit: 20 MB for the inline data payload; in practice keep the whole request (text + inline files) under ~20 MB or you’ll get 413. Use the Files API when larger. ([cloud.google.com](https://cloud.google.com/vertex-ai/generative-ai/docs/model-reference/inference?utm_source=openai))

File data (parts.fileData / fileUri)
- Cloud Storage URIs (gs://): up to 2 GB per file for gemini‑2.0‑flash and flash‑lite; specify the correct MIME type (e.g., image/jpeg, image/png, video/mp4, video/mov). ([cloud.google.com](https://cloud.google.com/vertex-ai/generative-ai/docs/model-reference/inference?utm_source=openai))
- HTTP/HTTPS URLs: allowed but smaller—audio/video/doc files must be ≤15 MB; you may include one video, one audio, and up to 10 images via HTTP URLs in a single request. ([cloud.google.com](https://cloud.google.com/vertex-ai/generative-ai/docs/model-reference/inference?utm_source=openai))
- YouTube: one public/unlisted video URL per request. ([cloud.google.com](https://cloud.google.com/vertex-ai/generative-ai/docs/model-reference/inference?utm_source=openai))

Upload file (Files API: media.upload, then use parts.fileData with file_uri)
- Retention: uploaded files are available for 48 hours. ([ai.google.dev](https://ai.google.dev/gemini-api/docs/document-processing))
- Storage/size quotas: project‑level file storage quota is 20 GB (quota metric file_storage_bytes); per‑file uploads up to 2 GB are supported in current published limits. ([ai.google.dev](https://ai.google.dev/gemini-api/docs/rate-limits?utm_source=openai))
- Use this path for anything that would push your request over the 20 MB inline limit or when you’ll reuse the same media across prompts. ([ai.google.dev](https://ai.google.dev/gemini-api/docs/document-processing))

Per‑request counts (useful bounds)
- Images: up to 3,600 image files per request (model‑dependent). ([ai.google.dev](https://ai.google.dev/gemini-api/docs/vision?utm_source=openai))
- Videos: up to 10 video files per request. ([firebase.google.com](https://firebase.google.com/docs/vertex-ai/input-file-requirements?utm_source=openai))

Notes
- video/quicktime and video/mov are used interchangeably in Google’s docs for .mov files; both are accepted. ([cloud.google.com](https://cloud.google.com/vertex-ai/generative-ai/docs/model-reference/inference?utm_source=openai))

If you need the exact limits for a specific model (e.g., Gemini 2.5 Flash vs 3 Pro), tell me which one and I’ll pull that table for you.
