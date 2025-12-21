# Real ECAPA (Speaker Embeddings) Setup

MetaVis supports embedding-based diarization via `METAVIS_DIARIZE_MODE=ecapa`.

There are currently two *different* embedding backends you can run:

1) **Pyannote community-1 (FBank + Embedding)**
   - Uses the downloaded CoreML bundles from FluidInference.
   - This is the default path used by the diarization integration tests in this repo.

2) **Real ECAPA-TDNN (waveform -> embedding)**
   - Built locally from SpeechBrain using CoreMLTools.
   - This is the “real ECAPA” backend.

## Build real ECAPA CoreML on macOS

Run:

```bash
scripts/build_ecapa_coreml_macos.sh
```

If your default `python3` is too new (e.g. Python 3.14+), set an explicit Python:

```bash
PYBIN=python3.12 scripts/build_ecapa_coreml_macos.sh
```

This generates:

- `assets/models/speaker/ecapa_tdnn_voxceleb.mlmodelc/`

## Run diarization with real ECAPA

```bash
export METAVIS_DIARIZE_MODE=ecapa
export METAVIS_ECAPA_MODEL="$PWD/assets/models/speaker/ecapa_tdnn_voxceleb.mlmodelc"
export METAVIS_ECAPA_SR=16000
export METAVIS_ECAPA_WINDOW=3.0
```

Then run your diarization/transcript pipeline as usual.

## Notes

- This model is exported with a **fixed input length** (default 3.0 seconds). Your diarization window size must match.
- If you see conversion failures, it’s usually a Torch/CoreMLTools compatibility issue. Try recreating the venv under `tools/ecapa_coreml_build/.venv`.
- The build currently requires **Python 3.11–3.13** (SpeechBrain dependencies break on Python 3.14 at time of writing).
