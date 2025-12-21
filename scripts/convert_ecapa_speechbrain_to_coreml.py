#!/usr/bin/env python3
"""Convert SpeechBrain ECAPA-TDNN speaker embedding model to CoreML.

This script is intended to produce a *real* ECAPA-TDNN embedding model (waveform -> embedding)
that MetaVis can use with `ECAPATDNNCoreMLSpeakerEmbeddingModel`.

Outputs:
- <out>/ecapa_tdnn_voxceleb.mlpackage

Notes:
- Conversion success depends on coremltools + torch compatibility on your machine.
- The exported model is fixed-shape for a specific window length (default: 3.0s @ 16kHz).
"""

from __future__ import annotations

import argparse
import os
from pathlib import Path

import numpy as np
import torch


def _patch_torchaudio_for_speechbrain() -> None:
    """SpeechBrain imports torchaudio and calls `torchaudio.list_audio_backends()`.

    Some torchaudio wheels (notably very new Python versions) may not expose that
    function even though basic import works. For our use-case (we supply waveform
    tensors directly), we can safely stub it to avoid import-time failures.
    """
    # SpeechBrain historically imported torchaudio at import-time. Newer SpeechBrain
    # versions have moved to soundfile, but some environments (or older versions)
    # still try to import torchaudio or call list_audio_backends().
    #
    # For this conversion script we do not need torchaudio at all (we pass waveforms
    # directly), so we stub torchaudio if missing.
    try:
        import torchaudio  # type: ignore
    except Exception:
        import sys
        import types

        torchaudio = types.ModuleType("torchaudio")  # type: ignore

        def _list_audio_backends() -> list[str]:
            return ["soundfile"]

        torchaudio.list_audio_backends = _list_audio_backends  # type: ignore[attr-defined]
        torchaudio.__dict__["__version__"] = "0.0-stub"
        sys.modules["torchaudio"] = torchaudio
        return

    if not hasattr(torchaudio, "list_audio_backends"):
        def _list_audio_backends() -> list[str]:
            return ["soundfile"]

        torchaudio.list_audio_backends = _list_audio_backends  # type: ignore[attr-defined]


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser()
    p.add_argument("--out", required=True, help="Output directory")
    p.add_argument("--seconds", type=float, default=3.0, help="Fixed window length in seconds")
    p.add_argument("--sr", type=int, default=16000, help="Sample rate")
    p.add_argument(
        "--model",
        default="speechbrain/spkrec-ecapa-voxceleb",
        help="SpeechBrain HF model id",
    )
    p.add_argument("--device", default="cpu", help="cpu or mps")
    return p.parse_args()


class ECAPAPipeline(torch.nn.Module):
    """Waveform -> embedding wrapper using SpeechBrain EncoderClassifier."""

    def __init__(self, classifier):
        super().__init__()
        self.classifier = classifier

    def forward(self, waveform: torch.Tensor) -> torch.Tensor:
        # waveform: [B, T]
        # SpeechBrain expects [B, T] float waveform at 16kHz.
        # encode_batch returns [B, 1, D] (typically). We squeeze to [B, D].
        emb = self.classifier.encode_batch(waveform)
        if emb.dim() == 3:
            emb = emb.squeeze(1)
        return emb


def main() -> None:
    args = parse_args()

    out_dir = Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)

    seconds = float(args.seconds)
    sr = int(args.sr)
    n = int(round(seconds * sr))

    device = torch.device(args.device)

    _patch_torchaudio_for_speechbrain()

    # Lazy import so the venv can be created before installing deps.
    from speechbrain.inference.speaker import EncoderClassifier

    classifier = EncoderClassifier.from_hparams(source=args.model, run_opts={"device": str(device)})

    model = ECAPAPipeline(classifier).to(device)
    model.eval()

    # Trace with fixed input shape.
    # Use non-zero audio to avoid tracing a degenerate path that could partially constant-fold.
    rng = np.random.default_rng(0)
    example = torch.from_numpy(rng.standard_normal((1, n), dtype=np.float32) * 0.05).to(device)
    with torch.no_grad():
        _ = model(example)

    # Sanity check that embeddings are not constant for different inputs.
    with torch.no_grad():
        example2 = torch.from_numpy(rng.standard_normal((1, n), dtype=np.float32) * 0.05).to(device)
        e1 = model(example).detach().cpu().numpy().ravel()
        e2 = model(example2).detach().cpu().numpy().ravel()
        cos = float(np.dot(e1, e2) / (np.linalg.norm(e1) * np.linalg.norm(e2) + 1e-12))
        print(f"Pre-trace embedding cosine similarity (random vs random): {cos:.6f}")

    traced = torch.jit.trace(model, example, check_trace=False)
    traced = torch.jit.freeze(traced)

    import coremltools as ct

    mlmodel = ct.convert(
        traced,
        inputs=[ct.TensorType(name="audio", shape=example.shape, dtype=np.float32)],
        convert_to="mlprogram",
        minimum_deployment_target=ct.target.macOS14,
        compute_precision=ct.precision.FLOAT16,
    )

    # Save as mlpackage (preferred); compilation to mlmodelc is done by `coremlc`.
    out_pkg = out_dir / "ecapa_tdnn_voxceleb.mlpackage"
    mlmodel.save(str(out_pkg))
    print(f"Wrote: {out_pkg}")


if __name__ == "__main__":
    main()
