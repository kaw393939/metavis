#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

export METAVIS_RUN_WHISPERCPP_TESTS=1

if [[ -z "${WHISPERCPP_BIN:-}" ]]; then
  if command -v whisper-cli >/dev/null 2>&1; then
    export WHISPERCPP_BIN="$(command -v whisper-cli)"
  else
    echo "ERROR: WHISPERCPP_BIN not set and whisper-cli not found on PATH." >&2
    echo "Run: bash scripts/install_whispercpp_coreml_macos.sh" >&2
    exit 1
  fi
fi

if [[ -z "${WHISPERCPP_MODEL:-}" ]]; then
  DEFAULT_MODEL="tools/whisper.cpp/models/ggml-tiny.en.bin"
  if [[ -f "${DEFAULT_MODEL}" ]]; then
    export WHISPERCPP_MODEL="${DEFAULT_MODEL}"
  else
    echo "ERROR: WHISPERCPP_MODEL not set (path to ggml-*.bin)." >&2
    echo "Run: bash scripts/install_whispercpp_coreml_macos.sh" >&2
    exit 1
  fi
fi

echo "Running Whisper E2E tests"
echo "- METAVIS_RUN_WHISPERCPP_TESTS=$METAVIS_RUN_WHISPERCPP_TESTS"
echo "- WHISPERCPP_BIN=$WHISPERCPP_BIN"
echo "- WHISPERCPP_MODEL=$WHISPERCPP_MODEL"

echo ""
swift test --filter TranscriptGenerateIntegrationTests
