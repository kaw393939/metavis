#!/usr/bin/env bash
set -euo pipefail

# Downloads CoreML speaker-embedding assets suitable for MetaVis embedding-based diarization.
#
# Source:
#   https://huggingface.co/FluidInference/speaker-diarization-coreml
#
# Output (default):
#   assets/models/speaker/FBank.mlmodelc/
#   assets/models/speaker/Embedding.mlmodelc/
#   assets/models/speaker/wespeaker_v2.mlmodelc/
#
# Usage:
#   ./scripts/download_wespeaker_coreml.sh
#   ./scripts/download_wespeaker_coreml.sh /custom/output/dir

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="${1:-$REPO_ROOT/assets/models/speaker}"
download_model() {
  local model_name="$1"
  local dest="$OUT_DIR/$model_name"
  local base_url="https://huggingface.co/FluidInference/speaker-diarization-coreml/resolve/main/${model_name}"

  mkdir -p "$dest/weights" "$dest/analytics"

  echo "Downloading $model_name → $dest"

  download() {
    local rel="$1"
    local url="$base_url/$rel"
    local dst="$dest/$rel"

    mkdir -p "$(dirname "$dst")"
    curl -L --fail --retry 3 --retry-delay 1 -o "$dst" "$url"
  }

  # These files are what CoreML needs to load the compiled bundle.
  download "metadata.json"
  download "model.mil"
  download "coremldata.bin"
  download "analytics/coremldata.bin"
  download "weights/weight.bin"
}

download_model "FBank.mlmodelc"
download_model "Embedding.mlmodelc"
download_model "wespeaker_v2.mlmodelc"

echo "Done."
echo
echo "Next (run diarization in ECAPA mode):"
cat <<EOF
  METAVIS_DIARIZE_MODE=ecapa \
  METAVIS_ECAPA_MODEL="$OUT_DIR/Embedding.mlmodelc" \
  METAVIS_ECAPA_FBANK_MODEL="$OUT_DIR/FBank.mlmodelc" \
  swift run MetaVisLab diarize --help
EOF
