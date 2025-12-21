#!/usr/bin/env bash
set -euo pipefail

# Build a *real* ECAPA-TDNN CoreML speaker embedding model (waveform -> embedding).
#
# This generates:
#   assets/models/speaker/ecapa_tdnn_voxceleb.mlmodelc/
#
# Requirements:
# - macOS
# - Xcode command line tools (`xcrun` provides `coremlc`)
# - Python 3.11–3.13 (Python 3.14 currently breaks SpeechBrain deps)

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${REPO_ROOT}/assets/models/speaker"
WORK_DIR="${REPO_ROOT}/tools/ecapa_coreml_build"
VENV_DIR="${WORK_DIR}/.venv"

say() { printf "%s\n" "$*"; }
die() { printf "ERROR: %s\n" "$*" >&2; exit 1; }

python_minor() {
  "$1" -c 'import sys; print(sys.version_info[0], sys.version_info[1])' 2>/dev/null || true
}

pick_python() {
  if [[ -n "${PYBIN:-}" ]]; then
    echo "${PYBIN}"
    return 0
  fi

  # Prefer Homebrew python@3.11 if available, to avoid accidentally picking up
  # a too-new default (e.g. 3.14) from another venv.
  if command -v brew >/dev/null 2>&1; then
    local b
    b="$(brew --prefix python@3.12 2>/dev/null || true)"
    if [[ -n "${b}" && -x "${b}/bin/python3.12" ]]; then
      echo "${b}/bin/python3.12"
      return 0
    fi
    b="$(brew --prefix python@3.11 2>/dev/null || true)"
    if [[ -n "${b}" && -x "${b}/bin/python3.11" ]]; then
      echo "${b}/bin/python3.11"
      return 0
    fi
  fi

  for candidate in python3.12 python3.11 python3.13 python3; do
    if command -v "${candidate}" >/dev/null 2>&1; then
      echo "${candidate}"
      return 0
    fi
  done

  return 1
}

if [[ "$(uname -s)" != "Darwin" ]]; then
  die "This script is intended for macOS."
fi

if ! command -v xcrun >/dev/null 2>&1; then
  die "xcrun not found. Install Xcode Command Line Tools: xcode-select --install"
fi

PYBIN="$(pick_python)" || die "Python not found. Install Python 3.12 or 3.11, or set PYBIN=/path/to/python3.12"
if ! command -v "${PYBIN}" >/dev/null 2>&1; then
  die "Python not found: ${PYBIN}"
fi

VER="$(python_minor "${PYBIN}")"
if [[ -z "${VER}" ]]; then
  die "Failed to query Python version for: ${PYBIN}"
fi

PYMAJOR="${VER%% *}"
PYMINOR="${VER##* }"
if [[ "${PYMAJOR}" != "3" || "${PYMINOR}" -lt 11 || "${PYMINOR}" -gt 13 ]]; then
  die "Unsupported Python version ${PYMAJOR}.${PYMINOR} for real ECAPA build. Use Python 3.11–3.13 (recommended 3.12) or set PYBIN=python3.12"
fi

mkdir -p "${OUT_DIR}" "${WORK_DIR}"

say "Repo: ${REPO_ROOT}"
say "Work: ${WORK_DIR}"

say "Python: $(${PYBIN} --version 2>&1)"

RECREATE_VENV=0
if [[ -x "${VENV_DIR}/bin/python" ]]; then
  VENV_VER="$(${VENV_DIR}/bin/python -c 'import sys; print(sys.version_info[0], sys.version_info[1])' 2>/dev/null || true)"
  VENV_MAJOR="${VENV_VER%% *}"
  VENV_MINOR="${VENV_VER##* }"
  if [[ -z "${VENV_VER}" || "${VENV_MAJOR}" != "3" || "${VENV_MINOR}" -lt 11 || "${VENV_MINOR}" -gt 13 ]]; then
    say "Recreating venv (was Python ${VENV_MAJOR:-?}.${VENV_MINOR:-?})"
    RECREATE_VENV=1
  elif [[ "${VENV_MAJOR}" != "${PYMAJOR}" || "${VENV_MINOR}" != "${PYMINOR}" ]]; then
    say "Recreating venv (was Python ${VENV_MAJOR}.${VENV_MINOR}, need ${PYMAJOR}.${PYMINOR})"
    RECREATE_VENV=1
  fi
else
  RECREATE_VENV=1
fi

if [[ "${RECREATE_VENV}" == "1" ]]; then
  rm -rf "${VENV_DIR}"
  say "Creating venv: ${VENV_DIR}"
  "${PYBIN}" -m venv "${VENV_DIR}"
fi

say "Installing Python deps (torch, speechbrain, coremltools)…"
"${VENV_DIR}/bin/pip" install -U pip

# Torch wheels are large; keep versions flexible.
"${VENV_DIR}/bin/pip" install -U torch numpy

# SpeechBrain audio I/O backend: soundfile (torchaudio is legacy and often missing on newer Pythons).
"${VENV_DIR}/bin/pip" install -U soundfile

"${VENV_DIR}/bin/pip" install -U speechbrain coremltools requests "huggingface_hub==0.19.4"

say "Converting SpeechBrain ECAPA to CoreML (.mlpackage)…"
PKG_OUT="${WORK_DIR}/out"
mkdir -p "${PKG_OUT}"
"${VENV_DIR}/bin/python" "${REPO_ROOT}/scripts/convert_ecapa_speechbrain_to_coreml.py" --out "${PKG_OUT}" --seconds 3.0 --sr 16000

MLPKG="${PKG_OUT}/ecapa_tdnn_voxceleb.mlpackage"
if [[ ! -d "${MLPKG}" ]]; then
  die "Expected mlpackage not found: ${MLPKG}"
fi

say "Compiling to .mlmodelc via coremlc…"
# coremlc outputs a directory named after the model.
TMP_COMPILED="${PKG_OUT}/compiled"
rm -rf "${TMP_COMPILED}"
mkdir -p "${TMP_COMPILED}"

xcrun coremlc compile "${MLPKG}" "${TMP_COMPILED}"

# Move/rename into assets/models/speaker.
# coremlc creates <TMP_COMPILED>/<name>.mlmodelc
FOUND="$(find "${TMP_COMPILED}" -maxdepth 1 -type d -name '*.mlmodelc' | head -n 1 || true)"
if [[ -z "${FOUND}" ]]; then
  die "coremlc did not produce a .mlmodelc under ${TMP_COMPILED}"
fi

DEST="${OUT_DIR}/ecapa_tdnn_voxceleb.mlmodelc"
rm -rf "${DEST}"
cp -R "${FOUND}" "${DEST}"

say "Done. Wrote: ${DEST}"

cat <<EOF

Run diarization with the real ECAPA model:

  export METAVIS_DIARIZE_MODE=ecapa
  export METAVIS_ECAPA_MODEL="$DEST"
  export METAVIS_ECAPA_SR=16000
  export METAVIS_ECAPA_WINDOW=3.0

Then run tests:
  export METAVIS_RUN_DIARIZE_TESTS=1
  export METAVIS_RUN_WHISPERCPP_TESTS=1
  export WHISPERCPP_BIN="$REPO_ROOT/tools/whisper.cpp/build/bin/whisper-cli"
  export WHISPERCPP_MODEL="$REPO_ROOT/tools/whisper.cpp/models/ggml-tiny.en.bin"
  swift test --filter MetaVisLabTests.DiarizeIntegrationTests

EOF
