# Awaiting Implementation

## Gaps & Missing Features
- None.

## Technical Debt
- **Conservative limits**: Default budgets are intentionally loose, but are env-tunable for CI/local tightening.

## Recommendations
- Optionally tighten budgets via env (e.g. `METAVIS_RENDER_FRAME_BUDGET_MS`, `METAVIS_EXPORT_BUDGET_SECONDS`, `METAVIS_RENDER_PEAK_RSS_DELTA_MB`).
