# Sprint 24d: TDD Plan

## 1. Unit Tests

### `MetaVisSimulationTests`
*   **`testEXRDecodingWithoutFFmpeg`**:
    *   **Setup:** Prefer an explicit test seam (e.g. env var `METAVIS_DISABLE_FFMPEG=1` or injected process runner) so tests don't mutate global PATH.
    *   **Action:** Decode an EXR-backed still via `ClipReader.texture(assetURL:timeSeconds:width:height:)`.
    *   **Assert:** Returns a valid `MTLTexture` using the native EXR path and does not invoke `ffmpeg`.
*   **`testEngineInitializationWithoutKwilliamsPath`**:
    *   **Setup:** Ensure there are no machine-specific absolute-path fallbacks enabled. Prefer a test seam (injected bundle/filesystem adapter) to simulate missing resources.
    *   **Action:** `MetalSimulationEngine.init()`
    *   **Assert:** Throws proper `ResourceError` or succeeds via Bundle, does NOT silently fail to fallback.

*   **`testClipReaderCacheClearOnPressureSignal`**:
    *   **Setup:** Populate `ClipReader` caches (frame cache + still cache + decoder cache).
    *   **Action:** Trigger a deterministic pressure signal (test seam) and/or call an explicit `clearCaches()` API.
    *   **Assert:** Cache sizes drop to 0 (or to a minimal configured bound).

### `MetaVisGraphicsTests`
*   **`testBundleResources`**:
    *   **Action:** `GraphicsBundleHelper.bundle`
    *   **Assert:** Returns a bundle that can be used with `device.makeDefaultLibrary(bundle:)` in the environments we support.

## 2. Integration Tests

### `GodTest Verification`
*   Run the "GodTest20s" recipe (ProjectRecipes.swift).
*   Verify that `macbeth` chart colors match ACEScg reference values exactly (using the `MetaVisLab` sensor command).

> Note: if a “GodTest” is too slow/flaky for CI, gate it behind an env var and keep the unit tests as the always-on safety net.

## 3. Manual Verification Steps

1.  **Build Release Build:** `swift build -c release`.
2.  **Verify Shaders:** Launch `MetaVisLab`. Check logs. Ensure "Loaded configured library" appears (not "Fallback").
3.  **Clean Room:** Run in a sandbox (if possible) or restricted user account to verify no implicit keychain/env-var access.
