# Sprint 01 Audit: Project Recipes

## Status: Mostly Implemented

## Accomplishments
- **ProjectRecipe Protocol**: Implemented in `Sources/MetaVisSession/ProjectRecipes.swift`.
- **Standard Recipes**: `SmokeTest2s` and `GodTest20s` implemented.
- **Session Integration**: `ProjectSession` initializes from recipes.
- **E2E Testing**: `RecipeE2ETests.swift` flow exists.

## Gaps & Missing Features
- **Governance Mapping**: `ProjectType` in `GovernanceTypes.swift` is defined but NOT mapped to default recipe IDs.
- **Recipe Registry**: No central registry to look up recipes by ID string. Recipes are hardcoded in `StandardRecipes`.

## Technical Debt
- **Hardcoded Recipes**: `StandardRecipes` is just a namespace for structs; there is no dynamic discovery or registry system.

## Recommendations
- Implement `RecipeRegistry` to allow looking up `ProjectRecipe` by string ID.
- Add `defaultRecipeID` to `ProjectType` in `GovernanceTypes.swift`.
