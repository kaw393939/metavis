# Render Policy Tiers

These are the **runtime** render configuration tiers used to deterministically configure the engine.

Tiers:
- `consumer` — prioritize speed and resilience.
- `creator` — prioritize quality while staying interactive.
- `studio` — prioritize strictness and auditability.

Where applied:
- `RenderRequest.renderPolicy` carries the tier into the engine.
- The tier resolves to concrete engine defaults via `RenderPolicyCatalog`.

Override at runtime:
- Set `METAVIS_RENDER_POLICY_TIER=consumer|creator|studio` to override the default tier selection used by export.

See tier docs:
- [consumer.md](consumer.md)
- [creator.md](creator.md)
- [studio.md](studio.md)
