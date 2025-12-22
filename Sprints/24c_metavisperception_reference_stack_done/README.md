# Sprint 24c — MetaVisPerception Reference-Grade Hardening

**Status (2025-12-22):** DONE.

This sprint is a direct response to the **binding directive** ("AI proposes → Engine verifies → Humans decide"):

- Keep perception **local, deterministic, auditable**.
- Make uncertainty and provenance **explicit and governed**.
- Improve **temporal coherence** and cross-signal identity binding.
- Treat **hardware awareness** (ANE/CoreML/Vision/Accelerate/Metal) as part of the design.

## Start Here
- Plan: `PLAN.md`
- Architecture: `ARCHITECTURE.md`
- Data dictionary: `DATA_DICTIONARY.md`
- TDD plan: `TDD_PLAN.md`
- Dependencies: `DEPENDENCIES.md`

## Why this sprint exists
`MetaVisPerception` already contains a strong deterministic sensor pipeline (`MasterSensorIngestor` → `MasterSensors`) and a growing set of device streams (tracks, masks, flow, depth, diarization).

However, the current **LLM boundary** types (`SemanticFrame`, `DetectedSubject`) are still placeholder-grade:
- Untyped `attributes: [String: String]`
- No governed confidence ontology
- No provenance
- No temporal aggregator above frames

Sprint 24c upgrades the **contracts** and **aggregation layer** so perception outputs are reference-grade.

## Key deliverables (high level)
- Formal, shared **confidence ontology** across perception outputs.
- Deterministic **TemporalContextAggregator** that produces higher-order events.
- Auditable **audio↔visual identity binding** over time (co-occurrence promotion/demotion).
- Explicit **provenance** in all LLM-facing semantics.
- A strengthened, versioned **SemanticFrame** contract (stable schema; no surprise fields).

## Implemented outputs
The reference stack is now emitted as versioned artifacts from the CLI pipeline (see `MetaVisLab diarize`):
- `temporal.context.v1.json`
- `identity.bindings.v1.json`
- `semantic.frame.v2.jsonl`

## Non-goals
- No generative vision models.
- No moving perception decisions into LLMs.
- No new end-user UX.

## Dependencies
- Sprint 24: speaker diarization artifacts + governed confidence sidecars.
- Sprint 24a: deterministic sensors (tracks/faces, stable IDs, warnings).
