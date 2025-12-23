#!/usr/bin/env bash
set -euo pipefail

# Overnight world-class color-cert runner
#
# Safe operations only:
# - Builds + runs targeted `swift test` parity tests (no source mutation)
# - Optionally runs the SDR tuning sweep grid
#
# Outputs:
# - test_outputs/overnight/<RUN_ID>/report.md
# - test_outputs/overnight/<RUN_ID>/logs/*.log
#
# Usage:
#   scripts/overnight_worldclass_colorcert.sh
#   SDR_SWEEP=1 scripts/overnight_worldclass_colorcert.sh
#   HDR_TUNE=1 METAVIS_HDR_LUT_PARITY_TUNE_VERBOSE=1 scripts/overnight_worldclass_colorcert.sh
#   METAVIS_FORCE_SHADER_ODT=1 METAVIS_FORCE_SHADER_ODT_HDR_TUNED=1 scripts/overnight_worldclass_colorcert.sh
#   PERFLOG=1 SDR_SWEEP=1 scripts/overnight_worldclass_colorcert.sh
#   METRICS=1 scripts/overnight_worldclass_colorcert.sh

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

TS="$(date +"%Y%m%d_%H%M%S")"
RUN_ID="overnight_${TS}"
OUT_DIR="$ROOT_DIR/test_outputs/overnight/$RUN_ID"
LOG_DIR="$OUT_DIR/logs"

mkdir -p "$LOG_DIR"

# Tunables
SDR_SWEEP="${SDR_SWEEP:-1}"          # 1 = run reduced 3D sweep in the SDR ΔE test
HDR_TUNE="${HDR_TUNE:-1}"            # 1 = enable built-in HDR tuning sweep in the HDR Macbeth test
PERFLOG="${PERFLOG:-0}"              # 1 = enable PerfLogger if your harness honors it
SKIP_READBACK="${SKIP_READBACK:-0}"  # 1 = set METAVIS_SKIP_READBACK=1 (perf-only scenarios)
METRICS="${METRICS:-0}"              # 1 = run scripts/run_metrics.sh at the end (can take longer)

export METAVIS_RUN_SHADER_LUT_PARITY=1

if [[ "$HDR_TUNE" == "1" ]]; then
  export METAVIS_SHADER_LUT_PARITY_TUNE=1
else
  unset METAVIS_SHADER_LUT_PARITY_TUNE || true
fi

if [[ "$PERFLOG" == "1" ]]; then
  export METAVIS_PERF_LOG=1
fi

if [[ "$SKIP_READBACK" == "1" ]]; then
  export METAVIS_SKIP_READBACK=1
fi

run_test() {
  local name="$1"
  local filter="$2"
  local logfile="$LOG_DIR/${name}.log"

  echo "==> Running: $filter" | tee "$logfile"
  ( time swift test -c debug --filter "$filter" ) 2>&1 | tee -a "$logfile"

  # Return only the key lines.
  grep -E "^\[ColorCert\]" "$logfile" || true
}

REPORT="$OUT_DIR/report.md"
{
  echo "# Overnight ColorCert Report"
  echo
  echo "- Run ID: $RUN_ID"
  echo "- Date: $(date)"
  echo "- Host: $(hostname)"
  echo "- Repo: $ROOT_DIR"
  echo "- Git HEAD: $(git rev-parse --short HEAD 2>/dev/null || echo 'unknown')"
  echo "- Git dirty: $(git diff --quiet 2>/dev/null && echo 'no' || echo 'yes')"
  echo "- Swift: $(swift --version 2>/dev/null | head -n 1 || echo 'unknown')"
  echo
  echo "## Environment"
  echo
  echo "- METAVIS_RUN_SHADER_LUT_PARITY=1"
  echo "- SDR_SWEEP=$SDR_SWEEP"
  echo "- HDR_TUNE=$HDR_TUNE (METAVIS_SHADER_LUT_PARITY_TUNE=${METAVIS_SHADER_LUT_PARITY_TUNE:-0})"
  echo "- PERFLOG=$PERFLOG"
  echo "- SKIP_READBACK=$SKIP_READBACK"
  echo "- METRICS=$METRICS"
  echo
  echo "## Results"
  echo
} > "$REPORT"

{
  echo "### HDR PQ1000"
  echo
  run_test "hdr_macbeth" "ACESShaderFallbackParityTests/test_shader_fallback_matches_hdr_pq1000_lut_macbeth_opt_in" | sed 's/^/- /'
  run_test "hdr_ramp" "ACESShaderFallbackParityTests/test_shader_fallback_matches_hdr_pq1000_lut_ramp_rolloff_opt_in" | sed 's/^/- /'
  echo
} >> "$REPORT"

{
  echo "### SDR Rec.709 (Studio)"
  echo
  if [[ "$SDR_SWEEP" == "1" ]]; then
    export METAVIS_SDR_LUT_PARITY_TUNE=1
  else
    unset METAVIS_SDR_LUT_PARITY_TUNE || true
  fi

  run_test "sdr_deltaE" "ACESShaderFallbackParityTests/test_shader_fallback_matches_sdr_lut_macbeth_deltaE2000_opt_in" | sed 's/^/- /'
  echo
} >> "$REPORT"

if [[ "$METRICS" == "1" ]]; then
  {
    echo "### Full Metrics"
    echo
    echo "- Running scripts/run_metrics.sh (may take longer)"
    echo
  } >> "$REPORT"

  ( time ./scripts/run_metrics.sh ) 2>&1 | tee "$LOG_DIR/run_metrics.log" || true

  {
    echo
    echo "- run_metrics.sh log: $LOG_DIR/run_metrics.log"
    echo
  } >> "$REPORT"
fi

{
  echo "## Artifacts"
  echo
  echo "- Report: $REPORT"
  echo "- Logs: $LOG_DIR"
  echo
  echo "## Next actions (when awake)"
  echo
  echo "- If SDR sweep finds a better BEST line, promote those constants into the tuned defaults."
  echo "- If HDR metrics regress, sweep HDR RGC params (strength/threshold/limit) and lock best."
  echo
} >> "$REPORT"

echo "Wrote report: $REPORT"
