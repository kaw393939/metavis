#!/usr/bin/env bash
set -euo pipefail

# Downloads pre-exported CoreML MobileSAM assets.
#
# Source repo (includes /coreml with .mlpackage + image_points_embeddings.bin):
#   https://github.com/AlessandroToschi/MobileSAM
#
# Output (default):
#   assets/models/mobilesam/coreml/ImageEncoder.mlpackage/
#   assets/models/mobilesam/coreml/PromptEncoder.mlpackage/
#   assets/models/mobilesam/coreml/MaskDecoder.mlpackage/
#   assets/models/mobilesam/coreml/image_points_embeddings.bin
#
# Usage:
#   ./scripts/download_mobilesam_coreml.sh
#   ./scripts/download_mobilesam_coreml.sh /custom/output/dir

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="${1:-$REPO_ROOT/assets/models/mobilesam}"
TMP_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

ZIP_URL="https://github.com/AlessandroToschi/MobileSAM/archive/refs/heads/master.zip"
ZIP_PATH="$TMP_DIR/MobileSAM-master.zip"

mkdir -p "$OUT_DIR"

echo "Downloading MobileSAM CoreML zip…"
curl -L --fail --retry 3 --retry-delay 1 -o "$ZIP_PATH" "$ZIP_URL"

echo "Extracting…"
unzip -q "$ZIP_PATH" -d "$TMP_DIR"

SRC_COREML="$TMP_DIR/MobileSAM-master/coreml"
if [[ ! -d "$SRC_COREML" ]]; then
  echo "ERROR: expected $SRC_COREML in zip" >&2
  exit 2
fi

DEST_COREML="$OUT_DIR/coreml"
rm -rf "$DEST_COREML"
mkdir -p "$DEST_COREML"

# Copy .mlpackage directories and the aux tensor.
cp -R "$SRC_COREML/"* "$DEST_COREML/"

echo ""
echo "Done. Assets are at: $DEST_COREML"
echo ""
echo "Optional (recommended for faster startup): precompile to .mlmodelc using Xcode tools:"
cat <<EOF
  xcrun coremlc compile "$DEST_COREML/ImageEncoder.mlpackage" "$OUT_DIR/compiled"
  xcrun coremlc compile "$DEST_COREML/PromptEncoder.mlpackage" "$OUT_DIR/compiled"
  xcrun coremlc compile "$DEST_COREML/MaskDecoder.mlpackage" "$OUT_DIR/compiled"
EOF
