# Awaiting Implementation

## Status
- ✅ Sprint complete (see IMPLEMENTED.md).

## Gaps & Missing Features
- None.

## Technical Debt
- **Hardcoded Registry**: `RecipeRegistry` is a manual switch (explicit list). This is acceptable for v1 determinism.

## Recommendations
- If/when needed: add a data-driven registry (JSON manifest or codegen) while preserving deterministic IDs.
