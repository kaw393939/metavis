#!/usr/bin/env bash
set -euo pipefail

# One-command perf + color-cert runner.
# Writes run artifacts under: test_outputs/metrics/<RUN_ID>/
#
# Usage:
#   scripts/run_metrics.sh [--run-id ID] [--ocio-ref] [--perf-sweep] [--sweep-repeats N] [--8k]
#
# Notes:
# - Always enables JSONL logging via METAVIS_PERF_LOG=1.
# - Always enables color-cert tests via METAVIS_RUN_COLOR_CERT=1.

RUN_ID=""
RUN_OCIO_REF=0
RUN_PERF_SWEEP=0
SWEEP_REPEATS=3
SWEEP_HEIGHTS=""
RUN_8K=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --run-id)
      RUN_ID="${2:-}"; shift 2 ;;
    --ocio-ref)
      RUN_OCIO_REF=1; shift ;;
    --perf-sweep)
      RUN_PERF_SWEEP=1; shift ;;
    --sweep-repeats)
      SWEEP_REPEATS="${2:-3}"; shift 2 ;;
    --sweep-heights)
      SWEEP_HEIGHTS="${2:-}"; shift 2 ;;
    --8k)
      RUN_8K=1; shift ;;
    -h|--help)
      sed -n '1,120p' "$0"; exit 0 ;;
    *)
      echo "Unknown arg: $1" >&2
      exit 2
      ;;
  esac
done

if [[ -z "$RUN_ID" ]]; then
  RUN_ID="$(date -u +"%Y%m%dT%H%M%SZ")"
fi

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="$REPO_ROOT/test_outputs/metrics/$RUN_ID"
mkdir -p "$OUT_DIR"

export METAVIS_PERF_LOG=1
export METAVIS_PERF_RUN_ID="$RUN_ID"
export METAVIS_RUN_COLOR_CERT=1
export METAVIS_RUN_COLOR_REFERENCE_MATCH=1

# Optional knobs.
if [[ "$RUN_8K" == "1" ]]; then
  export METAVIS_RUN_PERF_8K=1
fi

LOG="$OUT_DIR/swift_test.log"

echo "[run_metrics] runID=$RUN_ID" | tee "$LOG"
echo "[run_metrics] outDir=$OUT_DIR" | tee -a "$LOG"

pushd "$REPO_ROOT" >/dev/null

{
  echo "\n=== Perf: frame budget (360p) ==="
  swift test -c debug --filter MetaVisSimulationTests.RenderPerfTests/test_render_frame_budget

  echo "\n=== PerfMem: peak RSS delta ==="
  swift test -c debug --filter MetaVisSimulationTests.RenderMemoryPerfTests/test_render_peak_rss_delta_budget

  if [[ "$RUN_PERF_SWEEP" == "1" ]]; then
    echo "\n=== Perf: sweep common resolutions (policies) ==="
    export METAVIS_RUN_PERF_SWEEP=1
    export METAVIS_PERF_SWEEP_POLICIES=1
    export METAVIS_PERF_SWEEP_REPEATS="$SWEEP_REPEATS"
    if [[ -n "$SWEEP_HEIGHTS" ]]; then
      export METAVIS_PERF_SWEEP_HEIGHTS="$SWEEP_HEIGHTS"
    fi
    swift test -q --filter MetaVisSimulationTests.RenderPerfTests/test_render_perf_sweep_common_resolutions_opt_in
  fi

  echo "\n=== ColorCert: Macbeth (scene-referred ACEScg) ==="
  swift test -c debug --filter MetaVisSimulationTests.ACESMacbethACEScgDeltaETests

  echo "\n=== ColorCert: Macbeth (display-referred + studio LUT match + HDR smoke) ==="
  swift test -c debug --filter MetaVisSimulationTests.ACESMacbethDeltaETests

  if [[ "$RUN_OCIO_REF" == "1" ]]; then
    echo "\n=== ColorCertRef: OCIO re-bake matches committed LUTs ==="
    export METAVIS_RUN_OCIO_REF=1
    swift test -c debug --filter MetaVisSimulationTests.ACESOCIOBakeReferenceTests
  fi
} 2>&1 | tee -a "$LOG"

python3 "$REPO_ROOT/scripts/summarize_metrics.py" --run-id "$RUN_ID" --out-dir "$OUT_DIR" | tee -a "$LOG"

popd >/dev/null

echo "[run_metrics] done" | tee -a "$LOG"
