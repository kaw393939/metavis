# MetaVisServices TDD Plan

## Phase 1: Configuration & Core Infrastructure
**Goal:** Ensure we can securely load API keys and define the base protocols.
1.  [ ] **Test:** `ConfigurationLoaderTests` - Verify loading of `.env` file.
2.  [ ] **Implement:** `ConfigurationLoader` (Parser for .env).
3.  [ ] **Test:** `ServiceOrchestratorTests` - Verify initialization and provider registration.
4.  [ ] **Implement:** `ServiceOrchestrator` and `ServiceProvider` protocol.

## Phase 2: Google Provider (Gemini & Veo)
**Goal:** Connect to Google's 2025 APIs.
1.  [ ] **Test:** `GoogleProviderTests` - Verify request formatting for Gemini 3 Pro.
2.  [ ] **Implement:** `GoogleProvider` (HTTP Client for Vertex AI).
3.  [ ] **Test:** `GoogleProviderTests` - Verify response parsing (Live API check).

## Phase 3: ElevenLabs Provider
**Goal:** Connect to ElevenLabs for Audio.
1.  [ ] **Test:** `ElevenLabsProviderTests` - Verify TTS request construction.
2.  [ ] **Implement:** `ElevenLabsProvider`.
3.  [ ] **Test:** `ElevenLabsProviderTests` - Verify SFX generation.

## Phase 4: LIGM Integration
**Goal:** Wrap the local module.
1.  [ ] **Test:** `LIGMProviderTests` - Verify it can be registered as a provider.
2.  [ ] **Implement:** `LIGMProvider` (Adapter for `MetaVisImageGen`).

## Phase 5: Integration
**Goal:** End-to-end flow.
1.  [ ] **Test:** `IntegrationTests` - Request video from Orchestrator, receive Asset.
