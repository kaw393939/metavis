# ACES.metal

## Purpose
Shared ACES/ACEScct helper functions used by grading and tone mapping.

## Entrypoints
No compute kernels in this file (helpers only).

## Dependencies
Referenced by:
- `ColorGrading.metal`

## Notes
- Keep this file free of kernels so it can be included widely without PSO churn.
