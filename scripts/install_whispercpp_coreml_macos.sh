#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOLS_DIR="${REPO_ROOT}/tools"
WHISPERCPP_DIR="${TOOLS_DIR}/whisper.cpp"

say() {
  printf "%s\n" "$*"
}

die() {
  printf "ERROR: %s\n" "$*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1
}

if [[ "$(uname -s)" != "Darwin" ]]; then
  die "This script is intended for macOS (Darwin)."
fi

if ! need_cmd brew; then
  die "Homebrew is required. Install it from https://brew.sh then re-run."
fi

say "Repo: ${REPO_ROOT}"

say "Installing build deps via Homebrew (ffmpeg, cmake, git, python@3.11)…"
brew update >/dev/null
brew install ffmpeg cmake git python@3.11

PY311="$(brew --prefix python@3.11)/bin/python3.11"
if [[ ! -x "${PY311}" ]]; then
  die "python3.11 not found at ${PY311}."
fi

mkdir -p "${TOOLS_DIR}"

if [[ ! -d "${WHISPERCPP_DIR}/.git" ]]; then
  say "Cloning whisper.cpp into ${WHISPERCPP_DIR}…"
  git clone https://github.com/ggml-org/whisper.cpp "${WHISPERCPP_DIR}"
else
  say "Updating whisper.cpp (git pull)…"
  (cd "${WHISPERCPP_DIR}" && git pull --ff-only)
fi

say "Building whisper.cpp with Core ML enabled…"
(cd "${WHISPERCPP_DIR}" && \
  cmake -B build -DWHISPER_COREML=1 -DCMAKE_BUILD_TYPE=Release && \
  cmake --build build -j)

WHISPERCLI="${WHISPERCPP_DIR}/build/bin/whisper-cli"
if [[ ! -x "${WHISPERCLI}" ]]; then
  die "Build succeeded but whisper-cli not found at ${WHISPERCLI}."
fi

say "Ensuring ggml model is available (default: tiny.en)…"
MODEL_NAME="${WHISPERCPP_MODEL_NAME:-tiny.en}"
(cd "${WHISPERCPP_DIR}" && bash ./models/download-ggml-model.sh "${MODEL_NAME}")

MODEL_PATH="${WHISPERCPP_DIR}/models/ggml-${MODEL_NAME}.bin"
if [[ ! -f "${MODEL_PATH}" ]]; then
  die "Model download did not produce expected file: ${MODEL_PATH}"
fi

say "Optional: generate Core ML encoder (.mlmodelc) for ANE offload (one-time)."
say "This uses Python only for conversion (runtime is still whisper-cli)."
ENCODER_PATH="${WHISPERCPP_DIR}/models/ggml-${MODEL_NAME}-encoder.mlmodelc"
if [[ "${METAVIS_SKIP_COREML_ENCODER:-}" == "1" ]]; then
  say "Skipped (METAVIS_SKIP_COREML_ENCODER=1)."
elif [[ -d "${ENCODER_PATH}" ]]; then
  say "Core ML encoder already exists: ${ENCODER_PATH}"
else
  say "Generating Core ML encoder for ${MODEL_NAME}…"
  VENV_DIR="${WHISPERCPP_DIR}/.venv_coreml"
  "${PY311}" -m venv "${VENV_DIR}"
  "${VENV_DIR}/bin/pip" install -U pip >/dev/null
  "${VENV_DIR}/bin/pip" install -U coremltools ane_transformers openai-whisper >/dev/null
  (cd "${WHISPERCPP_DIR}" && PATH="${VENV_DIR}/bin:${PATH}" bash ./models/generate-coreml-model.sh "${MODEL_NAME}")
fi

cat <<EOF

Done.

Set these env vars for MetaVisLab:
  export WHISPERCPP_BIN="${WHISPERCLI}"
  export WHISPERCPP_MODEL="${MODEL_PATH}"

Run the real E2E test:
  scripts/run_whisper_e2e_tests.sh

Notes:
- whisper.cpp uses Core ML for the encoder when built with WHISPER_COREML=1.
- For ANE acceleration you typically also generate a matching encoder file:
    ${WHISPERCPP_DIR}/models/ggml-${MODEL_NAME}-encoder.mlmodelc
  (To skip generation: set METAVIS_SKIP_COREML_ENCODER=1.)

EOF
