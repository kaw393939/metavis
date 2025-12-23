# Search Results: whisper.cpp coreml ane

**Date:** 2025-12-20 18:40:14

## Answer

Do you want to run whisper.cpp on Apple Silicon using Core ML (ANE)? Here’s the short path.

What it does
- whisper.cpp can offload the encoder to Core ML, which uses Apple Neural Engine (ANE) on Apple Silicon for a big speedup vs CPU. The decoder stays in ggml; you can optionally use Metal for the rest. ([github.com](https://github.com/ggml-org/whisper.cpp))

How to enable Core ML + ANE (macOS)
- Install tools (Python 3.11 recommended): pip install ane_transformers openai-whisper coremltools. ([github.com](https://github.com/ggml-org/whisper.cpp))
- Generate the Core ML encoder once (example for base.en): ./models/generate-coreml-model.sh base.en → produces models/ggml-base.en-encoder.mlmodelc. ([github.com](https://github.com/ggml-org/whisper.cpp))
- Build with Core ML: cmake -B build -DWHISPER_COREML=1 && cmake --build build -j --config Release. ([github.com](https://github.com/ggml-org/whisper.cpp))
- Run as usual (ANE loads automatically on first run, which is slower due to compilation): ./build/bin/whisper-cli -m models/ggml-base.en.bin -f samples/jfk.wav. ([github.com](https://github.com/ggml-org/whisper.cpp))

Core ML + Metal combinations
- No Core ML/No Metal: build normally, run with -ng
- No Core ML/Metal: build normally, run without -ng
- Core ML/No Metal: build with WHISPER_COREML=1, run with -ng
- Core ML/Metal: build with WHISPER_COREML=1, run without -ng
- You can force Core ML to ANE, GPU, or CPU by editing coreml/whisper-encoder.mm (MLModelConfiguration.computeUnits). ([github.com](https://github.com/ggml-org/whisper.cpp/discussions/1722))

Extras
- Python binding with Core ML backend: WHISPER_COREML=1 pip install git+https://github.com/absadiki/pywhispercpp. ([github.com](https://github.com/absadiki/pywhispercpp?utm_source=openai))
- iOS/React Native wrapper supports loading the Core ML encoder (.mlmodelc) alongside the ggml model file. ([github.com](https://github.com/mybigday/whisper.rn?utm_source=openai))

Want a step-by-step for your setup? Tell me your target (macOS or iOS), Whisper model size, and whether you want Metal on for the decoder.
