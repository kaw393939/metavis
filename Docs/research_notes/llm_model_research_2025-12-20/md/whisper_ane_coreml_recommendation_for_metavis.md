# Whisper on ANE/Core ML — Recommendation for MetaVis (Dec 2025)

## TL;DR
For Apple Silicon acceleration on macOS/iOS, the most reliable “ANE Whisper” path today is **Core ML offload for the Whisper encoder**, with the **decoder staying outside Core ML**.

- **Best pragmatic choice (CLI / C++ pipeline):** `whisper.cpp` with `WHISPER_COREML=1` (encoder via Core ML → ANE).
- **Best pragmatic choice (Swift-first app/library):** **WhisperKit** (prebuilt Core ML bundles for multiple model sizes).
- **Not a good fit for Core ML/ANE:** `faster-whisper` (CTranslate2) currently targets CPU (Apple Accelerate) or NVIDIA CUDA; no Core ML / ANE backend.

## What “ANE optimized Whisper” usually means
In current open-source practice, “ANE Whisper” generally means:
- Convert **the encoder** to a Core ML model (`.mlmodelc` or `.mlpackage`) so Core ML can schedule it on **Neural Engine**.
- Run **the decoder loop** (autoregressive token generation) in a non-Core ML runtime (ggml/Metal/CPU/etc.).

This avoids the hardest part of full conversion: a stateful, step-wise decoder with KV cache.

## Recommended path for MetaVis (macOS M3 16GB)
### Phase 1 (fast win): integrate whisper.cpp Core ML encoder
This gives you a real ANE speedup with minimal risk.

Key points:
- `whisper.cpp` provides scripts to generate the Core ML encoder (`generate-coreml-model.sh`).
- Build with `-DWHISPER_COREML=1` to enable Core ML encoder usage.
- In Core ML you can control hardware selection via `MLModelConfiguration.computeUnits` (e.g. `.cpuAndNeuralEngine`) and verify with Instruments.

Why it fits MetaVis:
- Your current pipeline shells out to external tools and expects stable files. Replacing `whisper` (Python CLI) with a `whisper.cpp` binary is a clean swap.
- You can keep your existing transcript schema/tick mapping and only change the transcription backend.

### Phase 2 (Swift-first option): WhisperKit
If/when you want direct Swift API usage and iOS embedding:
- WhisperKit ships prebuilt Core ML bundles for many Whisper sizes (encoder/decoder/mel front-end), and a Swift package interface.
- This can become the “native” path for iOS devices, while macOS continues using whisper.cpp or also migrates.

### Phase 3 (hard mode): full Core ML encoder + decoder
Possible but higher complexity:
- The decoder is autoregressive and benefits from a one-token “step” function with KV-cache, which is more complex to export/convert.
- coremltools has improving support (e.g., torch export + stateful patterns), but this is a deeper R&D track.

## Notes on faster-whisper (why it’s not the ANE path)
- `faster-whisper` uses CTranslate2.
- CTranslate2 supports CPU (including Apple Accelerate) and CUDA; the common reports/issues indicate no MPS/Core ML device backend.

## Source trail (repo-local)
- Overview: `research_notes/llm_model_research_2025-12-20/md/whisper_coreml_ane_overview.md`
- whisper.cpp Core ML details: `research_notes/llm_model_research_2025-12-20/md/whisper_cpp_coreml_ane.md`
- Prebuilt Core ML bundles (WhisperKit, etc.): `research_notes/llm_model_research_2025-12-20/md/whisper_coreml_model_mlpackage.md`
- coremltools conversion notes: `research_notes/llm_model_research_2025-12-20/md/coremltools_convert_whisper.md`
- faster-whisper limitations: `research_notes/llm_model_research_2025-12-20/md/faster_whisper_coreml.md`

## Suggested next implementation step (if you want me to do it)
- Add a new MetaVisLab backend option: `--engine whisper-cli|whispercpp-coreml`.
- Implement a small adapter that parses whisper.cpp output (or invokes whisper.cpp JSON output mode if available) and maps it into your existing `transcript.words.v1.jsonl` contract.
