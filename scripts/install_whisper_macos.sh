#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

need_cmd() {
  command -v "$1" >/dev/null 2>&1
}

say() {
  printf "%s\n" "$*"
}

die() {
  printf "ERROR: %s\n" "$*" >&2
  exit 1
}

if [[ "$(uname -s)" != "Darwin" ]]; then
  die "This script is intended for macOS (Darwin)."
fi

if ! need_cmd brew; then
  die "Homebrew is required. Install it from https://brew.sh then re-run."
fi

say "Repo: ${REPO_ROOT}"

cat <<'EOF'

NOTE: This script installs the Python `whisper` CLI (openai-whisper).

MetaVis now uses whisper.cpp (Core ML encoder) for local transcription.

Use this instead:
  bash scripts/install_whispercpp_coreml_macos.sh

EOF

exit 0

say "Installing runtime deps via Homebrew (ffmpeg, python@3.11, pipx)…"
brew update >/dev/null
brew install ffmpeg python@3.11 pipx

if need_cmd pipx; then
  pipx ensurepath >/dev/null || true
else
  die "pipx was not found after brew install. Ensure brew's bin is on PATH."
fi

PY311="$(brew --prefix python@3.11)/bin/python3.11"
if [[ ! -x "${PY311}" ]]; then
  die "python3.11 not found at ${PY311}."
fi

say "Installing Whisper CLI (openai-whisper) via pipx using ${PY311}…"
if pipx list 2>/dev/null | grep -q "openai-whisper"; then
  pipx reinstall openai-whisper --python "${PY311}"
else
  pipx install openai-whisper --python "${PY311}"
fi

say "\nSanity checks:"
say "- ffmpeg: $(command -v ffmpeg)"
ffmpeg -version | head -n 1
say "- whisper: $(command -v whisper)"
whisper --help >/dev/null

cat <<'EOF'

Done.

Notes:
- This uses Python 3.11 because Torch/Whisper commonly lag behind bleeding-edge Python (your environment shows Python 3.14 in other tools).
- The Whisper CLI is `whisper` (installed into pipx’s bin dir, typically ~/.local/bin).

Example:
  whisper /path/to/audio_or_video.mp4 --model small --output_format vtt

EOF
