# Sprint 01 — Project Types as Recipes

## Goal
Create a first-class “recipe” concept so a `ProjectType` can produce a deterministic project setup: timeline tracks/clips, default `QualityProfile`, default governance/QC expectations.

## Why
- Removes bespoke setup code (CLI/tests) and makes projects reproducible.
- Aligns with `REFINED_ARCHITECTURE.md` intent: project types as repeatable topologies.

## Non-goals (v1)
- No UI.
- No persistence migration work beyond what’s required to run.
- No remote renderers.

## Acceptance criteria
- A `ProjectRecipe` exists and can:
  - build a timeline (tracks/clips) deterministically from a seed/config
  - choose a default `QualityProfile`
  - choose a default governance/QC policy bundle (initially minimal)
- `ProjectSession` can initialize from a recipe (or apply a recipe) without hand-wiring.
- An E2E test can:
  - create a project via recipe
  - export a short movie
  - run deterministic QC on the output
  - assert stable properties (duration, fps, resolution, non-silent audio if expected)

## Existing code likely touched
- `Sources/MetaVisCore/GovernanceTypes.swift` (wire `ProjectType` to recipe id)
- `Sources/MetaVisTimeline/Timeline.swift` (helpers for deterministic timeline construction)
- `Sources/MetaVisSession/ProjectSession.swift` (initialize/apply recipe)
- `Sources/MetaVisExport/VideoExporter.swift` (no behavior changes expected; invoked by tests)
- `Sources/MetaVisQC/VideoQC.swift` / `VideoContentQC.swift` (used in tests)
- `Sources/MetaVisSimulation/Features/StandardFeatures.swift` (generated patterns used as test data)

## New code to add
- `Sources/MetaVisSession/Recipes/ProjectRecipe.swift`
  - protocol/struct for recipes
  - deterministic seeding + defaults
- `Sources/MetaVisSession/Recipes/StandardRecipes.swift`
  - at least one recipe: `basicLabValidation` (SMPTE/ZonePlate/Macbeth generator)

## Deterministic generated-data strategy (no mocks)
- Use procedural generators already present as features/manifests:
  - SMPTE bars / zone plate / macbeth patterns
- Generate a timeline with a single clip of known duration (e.g. 2s) referencing a procedural generator node.
- Audio: generate deterministic tone via `MetaVisAudio` (or include a deterministic audio track generator if already present).

## Test strategy
- Primary: E2E “recipe → session → export → QC” tests.
- Avoid mocks:
  - Use real `MetalSimulationEngine` + `VideoExporter`.
  - Write output to a temp directory.
  - Validate with `VideoQC` (+ optional `VideoContentQC` checks).

## Work breakdown
1. Define `ProjectRecipe` abstraction and config/seed.
2. Implement 1–2 standard recipes.
3. Add session API: `applyRecipe(...)` or `init(recipe:...)`.
4. Add E2E tests using generated patterns and QC.
5. Update `MetaVisLab` to use a recipe (optional but recommended once tests pass).

## Risks
- Rendering/export determinism: ensure fixed seeds and avoid timing-based variability.
- Procedural generators must be available in the registry/bundle in tests.
