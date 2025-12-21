# Sprint 25: Cortana Partner Layer (Identity + Memory + Agent API)

## Goal
Transform the system from a "Passive Tool" into an "Active Partner" by adding the missing identity/memory and a high-level agent-facing API.

This sprint intentionally builds on the now-stable editing core (Sprints 15–18).

## Core Pillars
1) **Identity (Memory)**
- Connect face identity signals to stable `personId` semantics that can survive across clips/shots within deterministic constraints.
- Persist `personId` → `displayName` mapping in a project-level Cast List.

2) **Orchestration (Feedback)**
- Use the existing `FeedbackLoopOrchestrator` as the deterministic propose/evidence/QA runner.
- Define the approval gates and artifact writing that make proposals reviewable.

3) **Agent API (High-level actions)**
- Define an `AgentAction` / Agent API layer that composes lower-level primitives:
  - editing commands (`IntentCommand`)
  - perception-derived evidence
  - optional QA feedback loop

## Deliverables
- Project-level Cast List persisted with the project document.
- A minimal, typed Agent API surface (no UI required).
- One end-to-end workflow that uses Agent API + evidence + bounded edits.

## Out of Scope
- Fully autonomous editing without human direction.
- Cloud identity, cross-project identity graphs, or nondeterministic external services.

## Architecture: GBNF Alignment
*   **Source of Truth:** The `AgentAction` enum defined in this sprint must be treated as the **Canonical Source** for the GBNF grammar executed in **Sprint 32**.
*   **Codable:** Ensure `AgentAction` is fully `Codable` and schema-exportable.
