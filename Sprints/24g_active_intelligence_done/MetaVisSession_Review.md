# MetaVisSession Code Review

**Date:** 2025-12-21
**Reviewer:** Antigravity Agent
**Module:** `MetaVisSession`

## 1. Executive Summary

`MetaVisSession` is the "Application Layer" of the engine. it bridges the raw data model (`MetaVisTimeline`) with the editing intent (`MetaVisServices`) and the final output (`MetaVisExport`).

**Strengths:**
- **State Management:** `ProjectSession` maintains a clear `ProjectState` struct. Mutations are handled via a `dispatch(_: EditAction)` method, which is a unidirectional data flow pattern (Redux-like).
- **Undo/Redo:** The `UndoStep` closure-based approach inside `dispatch` is simple and effective for this scale.
- **Persistence:** `ProjectPersistence` uses deterministic JSON encoding (sorted keys) for the `ProjectDocumentV1`. This is critical for preventing git diff noise in project files.
- **Recipes:** The `ProjectRecipe` system allows for creating standardized starting points ("Smoke Test", "God Test").

**Critical Gaps:**
- **Command Architecture:** `CommandExecutor` (in the `Commands` directory) seems to be the engine for applying `UserIntent` objects, but the `StudioCommand.swift` file I looked for earlier was missing or mislocated. (Wait, `Commands` directory contained `CommandExecutor`, `IntentCommand`, `IntentCommandRegistry` but I didn't deep dive into them).
- **Concurrency:** `ProjectSession` is an actor, which is good. But `analyzeFrame` throttles analysis based on wall clock time using `Date()`, which might not be deterministic enough for regression testing.
- **Entitlements:** `EntitlementManager` has a hardcoded "UNLOCK_PRO_2025" backdoor. This is fine for dev but needs removal for production.

---

## 2. Detailed Findings

### 2.1 The "Brain" (`ProjectSession.swift`)
- **Actor Isolation:** Correctly protects state.
- **Intelligence Loop:** `processCommand` -> `LocalLLMService` -> `IntentParser` -> `applyIntent` -> `CommandExecutor` -> `dispatch`. This is the "Jarvis" loop.
- **Visual Context:** `analyzeFrame` pushes pixel buffers into `aggregator` to update `state.visualContext`. This allows the LLM to know "what's on screen".

### 2.2 Persistence (`ProjectPersistence.swift`)
- **Schema:** Simple V1 schema containing `createdAt`, `updatedAt`, `recipeID`, and `state`.
- **Determinism:** Explicitly uses `JSONWriting.write` (from `MetaVisCore` presumably?) or at least mentions deterministic encoding in comments.

### 2.3 Recipes (`ProjectRecipes.swift`)
- **SmokeTest2s:** A 2-second timeline with bars and tone. Perfect for quick CI checks.
- **GodTest20s:** A 20-second stress test with noise, sweeps, macbeth charts. This is the "Gold Standard" for export compliance.

---

## 3. Recommendations

1.  **Formalize Command Pattern:** The `IntentCommandRegistry` and `CommandExecutor` seem robust but ensure that *all* edits go through this pipeline (or `dispatch`) to guarantee Undo/Redo works for everything.
2.  **Mockable Entitlements:** The `EntitlementManager` should take a configuration object rather than hardcoding unlock codes.
3.  **Deterministic Time:** In `analyzeFrame`, pass in the `simulationTime` rather than using `Date()` if you want the "AI Analysis" to be reproducible during a render pass.
