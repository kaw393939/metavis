# Implemented Features

## Status: Implemented

## Accomplishments
- **ProjectRecipe Protocol**: Implemented in `Sources/MetaVisSession/ProjectRecipes.swift`.
- **Standard Recipes**: `SmokeTest2s` and `GodTest20s` implemented.
- **Session Integration**: `ProjectSession` initializes from recipes.
- **Recipe Registry (by ID)**: Central lookup by string recipe id via `Sources/MetaVisSession/RecipeRegistry.swift`.
- **Governance Mapping**: `ProjectType.defaultRecipeID` added in `Sources/MetaVisCore/GovernanceTypes.swift`.
- **Test Coverage**:
	- `Tests/MetaVisExportTests/RecipeE2ETests.swift` validates recipe → export → QC.
	- `Tests/MetaVisSessionTests/RecipeRegistryTests.swift` validates registry + default mappings.

## Acceptance criteria checklist
- ✅ `ProjectRecipe` exists and can build a deterministic timeline.
- ✅ Recipes choose defaults used by session/export (`ProjectSession(recipe:)` + `QualityProfile` passed by callers).
- ✅ `ProjectSession` supports recipe initialization and recipeID-based initialization.
- ✅ E2E test covers recipe → session → export → deterministic QC (including audio presence / not-silent).

## Known tradeoffs (intentional)
- `RecipeRegistry` is a hardcoded switch for determinism (acceptable for v1; documented in AWAITING_IMPLEMENTATION.md).
