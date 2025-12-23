# Search Results: coremltools convert whisper

**Date:** 2025-12-20 18:44:26

## Answer

Do you want to accelerate just Whisper’s encoder on Apple Silicon (most common/easy), or convert the full encoder+decoder for on‑device transcription? And what target(s) do you need (iOS, macOS) and model size (tiny/base/small/…)? 

If you just need the encoder (recommended first step)
- Install: pip install coremltools torch openai-whisper
- Convert the PyTorch encoder directly with coremltools:
  - Load Whisper (PyTorch), grab model.encoder
  - Create a dummy mel input shaped (1, 80, T) e.g., T=300
  - Call ct.convert on the encoder module with that example input, set compute_units=ct.ComputeUnit.ALL and (optionally) compute_precision=ct.precision.FLOAT16
  - Save the resulting .mlpackage
- Run decoder on CPU/GPU (PyTorch/C++) and feed it the encoder’s Core ML outputs. Many projects do this; whisper.cpp even ships a script to generate a Core ML encoder and uses ANE for the encoder only. ([github.com](https://github.com/HomeIncorporated/whisper.cpp-with-gpu?utm_source=openai))

If you want full on‑device (encoder+decoder) in Core ML
- This is doable but more involved because the decoder is autoregressive and benefits from a token‑by‑token “step” function with attention cache. Recent coremltools releases added support for torch.export and stateful models that helps with this flow. If you go this route, export a one‑token decoder step (inputs: previous tokens, encoder states, KV cache; outputs: logits and updated cache) and convert that with ct.convert. ([github.com](https://github.com/apple/coremltools/releases?utm_source=openai))
- You can also start from an existing Core ML implementation of Whisper to study the pieces (tokenizer, mel front‑end, encoder, decoder loop, ANE‑friendly ops). ([github.com](https://github.com/vade/OpenAI-Whisper-CoreML?utm_source=openai))

Notes and tips
- Prefer the PyTorch → Core ML path (ct.convert on a PyTorch module). ONNX → Core ML still works through coremltools, but Apple archived the old onnx‑coreml repo and recommends using coremltools’ built‑in converters. Dynamic/flexible shapes via ONNX can be tricky. ([github.com](https://github.com/onnx/onnx-coreml?utm_source=openai))
- coremltools is the supported way to convert models; install the latest version for best PyTorch and torch.export support. ([github.com](https://github.com/apple/coremltools?utm_source=openai))
- Core ML overview and (rare) custom layers: if you hit an unsupported op, you can fall back to a custom layer in Swift/Obj‑C, but try to stick to supported ops for ANE performance. ([developer.apple.com](https://developer.apple.com/jp/machine-learning/core-ml/?utm_source=openai))

Minimal encoder conversion example (Python)
- Load model: model = whisper.load_model("base").eval(); encoder = model.encoder
- Example input: example_mel = torch.randn(1, 80, 300)  # batch, mels, frames
- Convert:
  - mlmodel = ct.convert(encoder, inputs=[ct.TensorType(shape=example_mel.shape, name="mel")], compute_units=ct.ComputeUnit.ALL)
  - Optionally set compute_precision=ct.precision.FLOAT16 and a minimum_deployment_target that matches your app
- Save: mlmodel.save("whisper_encoder.mlpackage")

If you share your target platform (iOS/macOS), Whisper size, and whether you want encoder‑only or full pipeline, I can give you a runnable script tailored to that.
