# Search Results: Google image generation API December 2025 Vertex AI Imagen 3 endpoint predict request response inlineData

**Date:** 2025-12-13 07:32:44

## Answer

Here’s the up‑to‑date REST “predict” request/response you use in December 2025 to generate images with Vertex AI’s Imagen 3 models. Note: Imagen’s predict API does not use inlineData; when you need to send image bytes inline (for edits), use the field bytesBase64Encoded inside an image object. inlineData is used by Gemini’s generateContent, not by Imagen. ([docs.cloud.google.com](https://docs.cloud.google.com/vertex-ai/generative-ai/docs/model-reference/imagen-api))

Endpoint and model names
- POST https://LOCATION-aiplatform.googleapis.com/v1/projects/PROJECT_ID/locations/LOCATION/publishers/google/models/MODEL_VERSION:predict
- Common Imagen 3 model versions: imagen-3.0-generate-002, imagen-3.0-generate-001, imagen-3.0-fast-generate-001, imagen-3.0-capability-001. ([docs.cloud.google.com](https://docs.cloud.google.com/vertex-ai/generative-ai/docs/model-reference/imagen-api))

A) Text-to-image (Imagen 3.0 generate)
Request (JSON):
{
  "instances": [
    { "prompt": "A cinematic photo of a golden retriever running on a beach at sunset" }
  ],
  "parameters": {
    "sampleCount": 2,
    "sampleImageSize": "1024",
    "seed": 12345,
    "outputOptions": { "mimeType": "image/png" }
  }
}

Response (JSON):
{
  "predictions": [
    { "bytesBase64Encoded": "…", "mimeType": "image/png" },
    { "bytesBase64Encoded": "…", "mimeType": "image/png" }
  ]
}
- sampleCount controls how many images are returned in predictions.
- If any images are filtered by safety, they may be omitted unless you request reasons. ([docs.cloud.google.com](https://docs.cloud.google.com/vertex-ai/generative-ai/docs/model-reference/imagen-api))

Notes for Imagen 3.x:
- negativePrompt isn’t supported by imagen-3.0-generate-002 and newer. ([docs.cloud.google.com](https://docs.cloud.google.com/vertex-ai/generative-ai/docs/model-reference/imagen-api))
- Useful parameters include sampleCount, sampleImageSize (typical 64–4096 for Imagen 2/3), storageUri (to write to GCS), seed. ([cloud.google.com](https://cloud.google.com/vertex-ai/generative-ai/docs/reference/rest/Shared.Types/VisionGenerativeModelParams?utm_source=openai))

B) Edit (mask/inpaint) with inline image bytes (Imagen 3.0 capability)
- Use imagen-3.0-capability-001 and provide referenceImages with bytesBase64Encoded (this is the “inline data” equivalent for Imagen).
Request (JSON):
{
  "instances": [
    {
      "prompt": "Replace the sky with a dramatic sunset",
      "referenceImages": [
        {
          "referenceType": "REFERENCE_TYPE_RAW",
          "referenceId": 1,
          "referenceImage": { "bytesBase64Encoded": "B64_BASE_IMAGE" }
        },
        {
          "referenceType": "REFERENCE_TYPE_MASK",
          "referenceImage": { "bytesBase64Encoded": "B64_MASK_IMAGE" },
          "maskImageConfig": { "maskMode": "MASK_MODE_USER_PROVIDED", "dilation": 0.01 }
        }
      ]
    }
  ],
  "parameters": {
    "editMode": "EDIT_MODE_INPAINT_INSERTION",
    "sampleCount": 2,
    "outputOptions": { "mimeType": "image/png" }
  }
}

Response (JSON):
{
  "predictions": [
    { "bytesBase64Encoded": "BASE64_IMG_BYTES", "mimeType": "image/png" },
    { "bytesBase64Encoded": "BASE64_IMG_BYTES", "mimeType": "image/png" }
  ]
}
- The request and response fields above (bytesBase64Encoded, mimeType) are the canonical way to pass/receive inline image data with Imagen. ([docs.cloud.google.com](https://docs.cloud.google.com/vertex-ai/generative-ai/docs/model-reference/imagen-api-edit))

Predict method and schemas
- Call projects.locations.publishers.models.predict with instances of type VisionGenerativeModelInstance and parameters of type VisionGenerativeModelParams. The response returns predictions typed as VisionGenerativeModelResult, whose Image objects carry bytesBase64Encoded or gcsUri. ([docs.cloud.google.com](https://docs.cloud.google.com/vertex-ai/generative-ai/docs/reference/rest/v1beta1/projects.locations.publishers.models/predict?utm_source=openai))

Billing labels (optional)
- You may include labels in the request body (top-level) for Imagen billing usage only. ([cloud.google.com](https://cloud.google.com/vertex-ai/generative-ai/docs/reference/rest/v1/projects.locations.endpoints/predict?utm_source=openai))

If you want, tell me your region and model version and I’ll fill in a ready-to-run curl command with your exact endpoint URL and a minimal request body.
