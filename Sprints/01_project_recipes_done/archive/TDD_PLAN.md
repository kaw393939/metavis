# Sprint 01 — TDD Plan (Recipes)

## Testing principles
- No mocks.
- Prefer generated deterministic media.
- Tests validate full stack: `ProjectSession` → `VideoExporter` → file → `VideoQC`.

## New tests (write first)

### 1) `RecipeE2ETests.test_recipe_exports_qc_passes()`
- Location: `Tests/MetaVisSessionTests/RecipeE2ETests.swift`
- Steps:
  - Build `ProjectSession` from a recipe (new API).
  - Export 2 seconds @ 24 fps @ 1080p.
  - Run `VideoQC.validateMovie(...)` (or equivalent API).
  - Assert: duration in expected range; fps matches; resolution matches.

### 2) `RecipeE2ETests.test_recipe_is_deterministic_by_seed()`
- Create two sessions with same recipe + seed.
- Export two files.
- Validate deterministic equivalence:
  - Compare a small set of decoded keyframes deterministically (use existing comparator utilities such as `MetaVisCore/ImageComparator.swift` if appropriate).
  - If exact pixel equality is too strict, assert stable hashes from downsampled frames.

### 3) `RecipeE2ETests.test_recipe_governance_applies()`
- Use a `ProjectLicense` requiring watermark.
- Assert export succeeds and QC still passes.
- Assert watermark presence indirectly (e.g., content QC detects overlay differences vs non-watermarked baseline) OR via pixel sampling.

## Production code steps (make tests pass)
1. Add `Sources/MetaVisSession/Recipes/ProjectRecipe.swift`
   - `id`, supported `ProjectType`, `defaultQuality`, `defaultGovernancePolicy` (v1 can be minimal), `buildTimeline(seed:)`.
2. Add `Sources/MetaVisSession/Recipes/StandardRecipes.swift`
   - Implement at least `basicLabValidation`.
3. Update `Sources/MetaVisCore/GovernanceTypes.swift`
   - Add `ProjectType.defaultRecipeId` or mapping table.
4. Update `Sources/MetaVisSession/ProjectSession.swift`
   - Add API to apply recipe to state.

## Refactor phase
- Add small internal helpers for timeline construction.
- Ensure `StandardRecipes` uses only deterministic constants + explicit seed.

## Definition of done
- All new tests pass.
- `swift test` green.
- Recipe E2E test writes outputs into temp directory and cleans up.
