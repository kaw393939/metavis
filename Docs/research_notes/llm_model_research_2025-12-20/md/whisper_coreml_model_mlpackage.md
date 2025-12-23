# Search Results: Whisper CoreML model mlpackage

**Date:** 2025-12-20 18:42:52

## Answer

Do you need a ready-made Whisper Core ML .mlpackage, or guidance to build one?

Options you can download now
- Whisper large‑v3‑turbo as Core ML .mlpackage (includes Encoder.mlpackage and multiple decoder .mlpackages). Comes with a short Swift loading example. ([huggingface.co](https://huggingface.co/DRTR-J/whisper-large-v3-turbo-coreml-fp16/blob/main/whisper-large-v3-turbo-coreml-fp16/README.md?utm_source=openai))
- WhisperKit’s prebuilt Core ML bundles (mlmodelc format: AudioEncoder, TextDecoder, MelSpectrogram) for many Whisper sizes, ready to use with the WhisperKit Swift package. ([huggingface.co](https://huggingface.co/argmaxinc/whisperkit-coreml/tree/main))
- If you’re using whisper.cpp, Core ML encoder bundles (.mlmodelc zips) for all sizes are hosted here; these are not .mlpackage but work with whisper.cpp’s Core ML path. ([huggingface.co](https://huggingface.co/ggerganov/whisper.cpp?utm_source=openai))

Notes
- .mlpackage is the uncompiled Core ML package; you can compile it to .mlmodelc with Apple’s coremlc when integrating into apps. The DRTR‑J bundle above already ships as .mlpackage; WhisperKit and whisper.cpp repos mainly provide .mlmodelc. ([huggingface.co](https://huggingface.co/DRTR-J/whisper-large-v3-turbo-coreml-fp16/blob/main/whisper-large-v3-turbo-coreml-fp16/README.md?utm_source=openai))

If you tell me the exact Whisper size (tiny/base/small/medium/large‑v3/large‑v3‑turbo), target device (iPhone/iPad/Mac), and whether you prefer .mlpackage or .mlmodelc, I’ll point you to the best download and usage snippet.
