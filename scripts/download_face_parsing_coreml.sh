#!/usr/bin/env bash
set -euo pipefail

# Downloads a face-parsing CoreML model referenced by john-rocky/CoreML-Models.
#
# NOTE: This model is typically CelebAMask-HQ style parsing and does NOT provide
# a dedicated "teeth" class; teeth are usually part of an inner-mouth region.
#
# Source index:
#   https://github.com/john-rocky/CoreML-Models
#
# Output (default):
#   assets/models/face_parsing/FaceParsing.mlmodelc/   (preferred)
#   or assets/models/face_parsing/FaceParsing.mlmodel
#   or assets/models/face_parsing/FaceParsing.mlpackage/
#
# Usage:
#   ./scripts/download_face_parsing_coreml.sh
#   ./scripts/download_face_parsing_coreml.sh /custom/output/dir

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="${1:-$REPO_ROOT/assets/models/face_parsing}"
TMP_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

FILE_ID="1I_cu8x0k6d1AEV_VPLyMu3Pqg3hwmo7g"
RAW_PATH="$TMP_DIR/face_parsing_download"

mkdir -p "$OUT_DIR"

echo "Downloading face-parsing model from Google Drive (id=$FILE_ID)…"
python3 "$REPO_ROOT/scripts/download_gdrive_file.py" "$FILE_ID" "$RAW_PATH"

echo "Downloaded to: $RAW_PATH"

# Heuristic: if it's a zip, unpack and locate a model artifact.
if file "$RAW_PATH" | grep -qi "zip"; then
  echo "Detected zip; extracting…"
  unzip -q "$RAW_PATH" -d "$TMP_DIR/unzipped"

  # Pick the first plausible artifact.
  CANDIDATE=""
  while IFS= read -r p; do
    CANDIDATE="$p"
    break
  done < <(find "$TMP_DIR/unzipped" -maxdepth 4 \( -name "*.mlmodelc" -o -name "*.mlmodel" -o -name "*.mlpackage" \) | sort)

  if [[ -z "$CANDIDATE" ]]; then
    echo "ERROR: zip did not contain .mlmodel/.mlpackage/.mlmodelc" >&2
    exit 2
  fi

  SRC="$CANDIDATE"
else
  SRC="$RAW_PATH"
fi

base_name() {
  local p="$1"
  local b
  b="$(basename "$p")"
  # Strip one extension layer if present.
  echo "${b%.*}"
}

# Normalize into OUT_DIR as FaceParsing.*
if [[ "$SRC" == *.mlmodelc ]]; then
  rm -rf "$OUT_DIR/FaceParsing.mlmodelc"
  cp -R "$SRC" "$OUT_DIR/FaceParsing.mlmodelc"
  echo "Installed: $OUT_DIR/FaceParsing.mlmodelc"
  exit 0
fi

if [[ "$SRC" == *.mlpackage ]]; then
  rm -rf "$OUT_DIR/FaceParsing.mlpackage"
  cp -R "$SRC" "$OUT_DIR/FaceParsing.mlpackage"
  echo "Installed: $OUT_DIR/FaceParsing.mlpackage"
  echo ""
  echo "Optional (recommended): precompile to .mlmodelc"
  echo "  xcrun coremlc compile \"$OUT_DIR/FaceParsing.mlpackage\" \"$OUT_DIR\""
  exit 0
fi

# Otherwise assume .mlmodel (or unknown binary) and try to compile if possible.
DEST_MLMODEL="$OUT_DIR/FaceParsing.mlmodel"
cp -f "$SRC" "$DEST_MLMODEL"

echo "Installed: $DEST_MLMODEL"

if command -v xcrun >/dev/null 2>&1; then
  echo "Attempting to compile to .mlmodelc…"
  xcrun coremlc compile "$DEST_MLMODEL" "$OUT_DIR"
  echo "Compiled output should be under: $OUT_DIR/*.mlmodelc"
else
  echo "xcrun not found; skipping compilation. Install Xcode Command Line Tools and rerun if you want .mlmodelc." >&2
fi
