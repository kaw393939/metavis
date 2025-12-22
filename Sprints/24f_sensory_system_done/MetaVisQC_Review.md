# MetaVisQC Code Review

**Date:** 2025-12-21
**Reviewer:** Antigravity Agent
**Module:** `MetaVisQC`

## 1. Executive Summary

`MetaVisQC` is the quality control and safety layer of the MetaVis system. It combines deterministic signal processing (`VideoQC`, `VideoContentQC`) with probabilistic AI judgement (`GeminiQC`) to approve or reject deliverables.

**Strengths:**
- **Layered Defense:** QC is applied in layers. `VideoQC` validates technical specs first (resolution, duration). `VideoContentQC` checks for content validity (black frames, frozen video). `GeminiQC` is the final, expensive check for semantic quality.
- **Privacy First:** `GeminiQC` respects a rigorous `AIUsagePolicy` (defined in Core). It includes a "Local Gate" that blocks media upload if the content is trivially invalid (e.g. black screen), saving API costs and reducing data exposure.
- **Determinism:** Like Perception, `VideoContentQC` uses deterministic downsampling and specific hashing algorithms (perceptual hash, luma signature) to ensure consistent results.

**Critical Gaps:**
- **Fingerprinting Fallback:** `VideoContentQC` attempts to use Metal for fingerprinting but falls back to CPU. The CPU path uses `CoreGraphics` which is fine for small thumbnails but slow for 4K.
- **Memory:** `GeminiQC.extractJPEGs` uses `AVAssetImageGenerator` which is efficient, but `extractJPEGs` loads all JPEG data into memory at once. For long clips with many keyframes, this could spike memory.
- **Error Handling:** `VideoQC` throws generic `NSError` with code integers that are magic numbers.

---

## 2. Detailed Findings

### 2.1 AI Gateway (`GeminiQC.swift`)
- **Integration:** Wraps `MetaVisServices.GeminiClient`.
- **Prompt Engineering:** Uses `GeminiPromptBuilder` to construct a context-rich prompt including metrics and privacy policy context.
- **Safety:** Explicitly checks `usage.policy.allowsNetworkRequests` before doing anything.

### 2.2 Content Analysis (`VideoContentQC.swift`)
- **Black Frame Detection:** The "Local Gate" analyzes luma histograms to detect near-black frames. This is a critical cost-saving feature.
- **Fingerprinting:** Calculates RGB mean/std-dev and Perceptual Hash. This is likely used for "deduplication" or ensuring the output matches the timeline intent (regression testing).

### 2.3 Technical Validation (`VideoQC.swift`)
- **Specs:** Validates Duration, Resolution, FPS, and "Sample Count" (to detect encoder dropouts).
- **Audio:** Checks for presence of audio track and silence (peak < -66dB).

---

## 3. Recommendations

1.  **Structured Errors:** Define a proper `QCError: Error` enum instead of using `NSError` with magic integers.
2.  **Streaming Hashes:** Implement a streaming hasher for large files so `VideoContentQC` doesn't need to retain large buffers.
3.  **Governance Config:** The allowed `AIUsagePolicy` should be injected from a central configuration service rather than instantiated ad-hoc.
