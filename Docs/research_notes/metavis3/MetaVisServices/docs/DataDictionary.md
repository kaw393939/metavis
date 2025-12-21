# MetaVisServices Data Dictionary

## 1. Enums

### `ServiceCapability`
Defines what a provider can do.
*   `textGeneration`: LLM/Chat (Gemini).
*   `imageGeneration`: 2D Images (LIGM, Gemini Image).
*   `videoGeneration`: Video clips (Veo).
*   `audioGeneration`: Music/SFX (Lyria, ElevenLabs).
*   `speechSynthesis`: TTS (ElevenLabs).
*   `speechToSpeech`: Voice Cloning/Dubbing (ElevenLabs).
*   `sceneAnalysis`: Computer Vision/Reasoning (Gemini).

### `ProviderType`
*   `google`: Google Cloud / Vertex AI.
*   `elevenLabs`: ElevenLabs.
*   `ligm`: Local Image Generation Module.

## 2. Structs

### `ServiceConfig`
Configuration for a provider.
*   `apiKey`: String (Secure).
*   `projectId`: String (Optional, for Google).
*   `endpoint`: URL (Optional).
*   `options`: [String: Any] (Custom options).

### `GenerationRequest`
A unified request structure.
*   `id`: UUID.
*   `type`: ServiceCapability.
*   `prompt`: String.
*   `parameters`: [String: Any] (e.g., duration, aspect ratio, seed).
*   `context`: [String: Any] (Optional context for the model).

### `GenerationResponse`
The result of a generation task.
*   `id`: UUID.
*   `requestId`: UUID.
*   `status`: Status (success, failure).
*   `data`: Data? (Raw bytes or JSON).
*   `artifacts`: [ServiceArtifact] (The generated content).
*   `metrics`: ServiceMetrics.

### `ServiceArtifact`
A generated item.
*   `type`: ArtifactType (video, audio, image, text).
*   `uri`: URL (Local or Remote).
*   `metadata`: [String: Any].

### `ServiceMetrics`
Observability data.
*   `latency`: TimeInterval.
*   `tokenCount`: Int.
*   `costEstimate`: Double.
