#!/usr/bin/env bash
set -euo pipefail

# Runs the perf sweep across consumer/creator/studio tiers with repeats.
# Usage:
#   scripts/run_perf_sweep_policies.sh [repeats]
#
# Defaults:
# - repeats=3

REPEATS="${1:-3}"

export METAVIS_RUN_PERF_SWEEP=1
export METAVIS_PERF_LOG=1
export METAVIS_PERF_SWEEP_POLICIES=1
export METAVIS_PERF_SWEEP_REPEATS="$REPEATS"

# Optional knobs (leave unset by default):
# export METAVIS_RUN_PERF_8K=1
# export METAVIS_PERF_BLUR_BREAKDOWN=1
# export METAVIS_PERF_SWEEP_MAX_HEIGHT=2160

swift test -q --filter MetaVisSimulationTests.RenderPerfTests/test_render_perf_sweep_common_resolutions_opt_in
