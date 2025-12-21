# MetaVisServices Specification

## 1. Overview
`MetaVisServices` is the unified gateway for all Generative AI operations within the MetaVis ecosystem. It abstracts the complexity of interacting with disparate providers (Google Cloud, ElevenLabs, Local GPU) behind a single, type-safe, and observable interface.

## 2. Design Philosophy
*   **Provider Agnostic:** The consumer (UI/Timeline) requests a "Video Generation" or "Text Analysis" without needing to know the specific API endpoints.
*   **Real-Time & Async:** Supports both streaming (for chat/voice) and long-running async jobs (for video generation).
*   **Scientific Rigor:** All outputs are wrapped in metadata-rich structures (provenance, generation parameters, seed) to support the "MetaVis Lab" QA process.
*   **No Mocks (Production Ready):** Designed to load real API keys from the environment and interact with live services.

## 3. Supported Providers
### 3.1. Google Cloud (Vertex AI)
*   **Gemini 3 Pro:** Reasoning, Scene Analysis, "Copilot" chat.
*   **Veo 3.1:** High-fidelity Video Generation.
*   **Lyria:** Music and Audio Generation.

### 3.2. ElevenLabs
*   **TTS:** High-quality voice synthesis.
*   **Speech-to-Speech:** Performance cloning.
*   **Sound Effects:** Text-to-SFX generation.

### 3.3. LIGM (Local Image Generation Module)
*   **Procedural/ML:** Local, deterministic image generation for QA and textures.
*   **Zero Latency:** Direct GPU-to-Texture pipeline.

## 4. Core Features
*   **Unified Configuration:** Loads secrets from `.env`.
*   **Service Registry:** Dynamic registration of providers.
*   **Metrics:** Tracks latency, token usage, and error rates.
*   **Asset Integration:** Automatically converts service responses into `MetaVisCore.Asset` types.
