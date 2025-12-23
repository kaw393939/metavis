# Search Results: whisper.cpp ojf json segments t0 t1

**Date:** 2025-12-20 18:54:36

## Answer

- -ojf in whisper.cpp = “output JSON (full)”. It writes a richer JSON than -oj, including per-segment plus per-word details (ids, probabilities, word timestamps, etc.). Example discussion and usage show -ojf producing fields like timestamps (human-readable) and offsets (milliseconds). ([github.com](https://github.com/ggerganov/whisper.cpp/issues/1798))

- segments = the top-level array of recognized chunks. Each segment has its text and timing.

- t0 and t1 = the segment start/end returned by the C API in 10 ms units (not milliseconds). Convert with:
  - seconds = t0/100 and t1/100
  - milliseconds = t0*10 and t1*10
This unit detail is documented via the API functions whisper_full_get_segment_t0_from_state / t1. ([github.com](https://github.com/ggml-org/whisper.cpp/issues/3370))

- In -ojf JSON specifically, you’ll often also see:
  - timestamps: { from: "hh:mm:ss,ms", to: "hh:mm:ss,ms" }
  - offsets: { from: <ms>, to: <ms> }
for words or tokens inside each segment. These are already human-friendly strings and raw millisecond offsets, respectively. ([github.com](https://github.com/ggml-org/whisper.cpp/issues/3207?utm_source=openai))

If you share a short JSON snippet you’re looking at, I can point to the exact fields.
