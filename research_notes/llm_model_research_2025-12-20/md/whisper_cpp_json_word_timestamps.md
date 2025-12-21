# Search Results: whisper.cpp whisper-cli -oj word timestamps

**Date:** 2025-12-20 18:52:40

## Answer

Use whisper-cli like this to get JSON with per-word timestamps:
- whisper-cli -m models/ggml-base.en.bin -f input.wav -ml 1 -ojf -of output

Notes:
- -ml 1 forces word-level segmentation so each “word” has its own timestamp. ([github.com](https://github.com/ggml-org/whisper.cpp?utm_source=openai))
- -ojf writes “full” JSON (richer than -oj), which includes per-word details/timestamps; use -of to set the output filename stem. ([github.com](https://github.com/lloydchang/ggerganov-whisper.cpp?utm_source=openai))
- If you only want segment-level JSON, use -oj instead of -ojf. ([github.com](https://github.com/lloydchang/ggerganov-whisper.cpp?utm_source=openai))
- There’s also -owts to generate a karaoke-style script (not JSON) that highlights words over time. ([github.com](https://github.com/ggml-org/whisper.cpp?utm_source=openai))

If you want me to tailor the command (e.g., non-WAV input, VAD, diarization), tell me your exact needs.
