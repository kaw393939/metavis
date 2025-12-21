# Search Results: faster-whisper coreml

**Date:** 2025-12-20 18:41:43

## Answer

Do you want to run faster-whisper on Apple’s Core ML/ANE?

- Short answer: faster-whisper doesn’t support Core ML (or Metal/MPS). It runs on CPU (including Apple Accelerate) and on NVIDIA GPUs via CUDA. CTranslate2 (the runtime behind faster‑whisper) documents Apple Accelerate for CPU but has no MPS/Core ML device, and an open issue shows mps is unsupported; related tools expose only cpu/cuda flags. ([github.com](https://github.com/OpenNMT/CTranslate2?utm_source=openai))

What you can do instead
- If you stay with faster‑whisper on Mac:
  - Use CPU with 8‑bit to get decent speed on Apple Silicon:
    - from faster_whisper import WhisperModel
      model = WhisperModel("small", device="cpu", compute_type="int8")
      segments, info = model.transcribe("audio.wav")
  - This uses CTranslate2 + Apple Accelerate on CPU. ([github.com](https://github.com/SYSTRAN/faster-whisper?utm_source=openai))
- If you specifically need Core ML/ANE acceleration:
  - Use whisper.cpp, which has a Core ML encoder path on Apple Silicon:
    - Generate Core ML model: ./models/generate-coreml-model.sh base.en
    - Build with Core ML: cmake -B build -DWHISPER_COREML=1 && cmake --build build -j
    - Run: ./build/bin/whisper-cli -m models/ggml-base.en.bin -f samples/jfk.wav
    - This routes the encoder to ANE via Core ML. ([github.com](https://github.com/ggml-org/whisper.cpp?utm_source=openai))
  - Or consider MLX/Core ML-first projects aimed at Apple Silicon:
    - Lightning Whisper MLX (pure MLX) ([github.com](https://github.com/mustafaaljadery/lightning-whisper-mlx?utm_source=openai))
    - Lightning‑SimulWhisper (MLX decoder + Core ML encoder) ([github.com](https://github.com/altalt-org/Lightning-SimulWhisper?utm_source=openai))

If you tell me your target (macOS CLI, iOS app, real‑time/streaming, model size), I can give exact setup steps and flags.
