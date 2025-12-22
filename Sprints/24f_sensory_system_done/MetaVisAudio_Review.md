# MetaVisAudio Code Review

**Date:** 2025-12-21
**Reviewer:** Antigravity Agent
**Module:** `MetaVisAudio`

## 1. Executive Summary

The `MetaVisAudio` module provides a robust, offline-capable audio rendering engine built on top of `AVAudioEngine`. It supports timeline-based composition, basic procedural audio generation, and a mastering chain with "AI Engineer" capabilities (automatic loudness normalization).

**Strengths:**
- **Architecture:** Clean separation between Graph Building (`AudioGraphBuilder`), Rendering (`AudioTimelineRenderer`), and Mastering (`AudioMasteringChain`).
- **Determinism:** Strong focus on deterministic rendering (seeded noise, stateless signal generation where possible).
- **Memory Management:** `FileClipStream` implements a bounded ring buffer to stream file-backed assets without loading entire files into RAM.
- **Safety:** Usage of manual rendering mode prevents real-time glitches from affecting export quality.

**Critical Gaps:**
- **Loudness Standards:** `LoudnessAnalyzer` uses RMS as a proxy for LUFS. This is not compliant with EBU R128 or AES streaming standards, which require K-weighting. The current implementation is an approximation.
- **Hardcoded Configuration:** EQ bands in `AudioMasteringChain` and sample rates (48kHz) are hardcoded in several places.
- **Error Handling:** `RenderError` is minimal and may not provide enough context for debugging complex render failures.
- **Test Coverage:** (Implicit) No unit tests were visible in the source directory scan.

---

## 2. Detailed Findings

### 2.1 Architecture & Graph Building (`AudioGraphBuilder.swift`)

- **Design:** adopting `AVAudioEngine` for offline rendering is the correct choice for Apple platforms.
- **Node Management:** The builder correctly detaches nodes (`managedNodes`) and cancels streams (`activeStreams`) between renders to prevent graph leakage.
- **Procedural Audio:** The `ligm://` scheme support (Sine, Noise, Sweep, Impulse) is excellent for unit testing and verifying signal path integrity without external assets.
- **Observation:** `FileClipStream` uses `AVAssetReader` in a linear streaming fashion. This is efficient for sequential playback.
    - **Risk:** High seek latency if used for interactive playback (scrubbing), as `AVAssetReader` must be re-initialized or seeked. The current implementation creates a new stream for each render call (`createFileNode`), which mitigates state issues but might be heavy on file descriptors if thousands of clips exist.

### 2.2 Rendering & Mastering (`AudioTimelineRenderer.swift`, `AudioMasteringChain.swift`)

- **Manual Rendering:** Properly uses `.offline` mode.
- **V-Sync/Chunking:** `renderChunks` allows breaking down the generic timeline into manageable buffers, crucial for long exports to avoid memory exhaustion.
- **Mastering Chain:**
    - The "AI Engineer" (`EngineerAgent`) currently measures a 10s prefix. This is a heuristic that might miss the loudest section of a long program (e.g., an explosion at 5m). *Recommendation: Implement a fast-scan or statistical sampling approach for longer content.*
    - **Limiter:** Uses a hard-knee limiter implemented with vDSP. While performant, it might introduce distortion on heavy peaks.

### 2.3 Audio Analysis (`LoudnessAnalyzer.swift`)

- **Issue [P1]:** The comment `// Approximate using RMS for V1` confirms that true LUFS measurement is missing. RMS is not equal to LUFS.
    - **Impact:** Content normalized to "-14 LUFS" using this RMS implementation will likely be louder than allowed on platforms like Spotify/YouTube, potentially leading to further penalty compression by those platforms.
    - **Fix:** Implement K-weighting filter (Start-High pass + Shelf) before RMS calculation to adhere to ITU-R BS.1770-4.

### 2.4 Concurrency & Safety

- **Sendable Compliance:** `FileClipStream` is marked `@unchecked Sendable`.
    - **Verification:** It uses `NSCondition` (lock) for mutable state protection (`storage`, `writeFrameIndex`, etc.) and a serial `decodeQueue` for `AVAssetReader` operations. This pattern is generally thread-safe.
- **Unsafe Pointers:** Extensive use of `UnsafeMutableAudioBufferListPointer` and `vDSP`.
    - `AudioGraphBuilder` (L176+): Manual silence filling and buffer access. Logic appears sound with bounds checking (`activeStartInCallback`, `activeEndInCallback`).
    - `FileClipStream` (L541, L554): `update(from:count:)` is used safely within locks and bounds checks.

### 2.5 Code Style & Maintainability

- **Documentation:** Public methods have minimal but clear documentation.
- **Diagnostics:** `FileAudioStreamingDiagnostics` is a nice touch for debugging streaming behavior.
- **Constants:** Magic numbers exist (e.g., `48000.0` sample rate, EQ frequencies).
    - *Recommendation: Move `standardSampleRate` and default EQ config to a `AudioConfig` struct.*

---

## 3. Recommendations

1.  **Upgrade Loudness Analyzer:** Prioritize implementing true EBU R128 (K-weighted) loudness measurement.
2.  **Configurable Mastering:** Allow injecting a custom mastering configuration (EQ points, Dynamics settings) rather than relying on hardcoded defaults.
3.  **Full-Program Analysis:** Update `EngineerAgent` to support "smart scan" (checking random chunks or a usage-weighted map) to find the true peak/Loudness of the timeline.
4.  **Unit Tests:** Ensure `AudioSignalGenerator` is used in a test suite to verify graph output against known reference signals (e.g. render a sine wave and assert RMS).

