# Sprint 24e: TDD Plan

## 1. Unit Tests

### `MetaVisLabTests`
*   **`testGeminiAnalyzeUsesExporter`**:
    *   **Setup:** Mock `TraceSink`.
    *   **Action:** internal `GeminiAnalyzeCommand.run(...)`.
    *   **Assert:** Verify `export.begin` trace event is emitted. Verify NO `Process` (ffmpeg) launch occurs.

**Repo reality (2025-12-22):** There is no `MetaVisLabTests` coverage for `GeminiAnalyzeCommand` yet; existing Lab tests focus on transcript/diarize/sensors flows.

### `MetaVisIngestTests`
*   **`testNoisePluginRegistration`**:
    *   **Setup:** `LIGMDevice`. Register `NoisePlugin`.
    *   **Action:** `device.perform(action: "generate", params: ["prompt": "noise://white"])`
    *   **Assert:** Returns valid Asset ID.
*   **`testPluginRouting`**:
    *   **Setup:** Register two plugins ("noise", "dummy").
    *   **Action:** Call generate with prompts targeting each.
    *   **Assert:** Correct plugin is invoked.

**Repo reality (2025-12-22):** `Tests/MetaVisIngestTests/LIGMDeviceTests.swift` currently asserts the stub behavior (it expects a synthetic `ligm://` URL). This test will need to be rewritten once plugins are introduced.

## 2. Integration Tests

### `CLI Path Verification`
*   Run: `swift run MetaVisLab gemini-analyze --input test.mov --out <custom_output_dir>`
*   Verify: `<custom_output_dir>/proxy.mp4` exists.

**Note:** The current CLI flag is `--out` (not `--output`) and the proxy file name is `gemini_proxy_360p_60s.mp4`.
