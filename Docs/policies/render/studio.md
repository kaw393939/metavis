# Render Policy: studio

Intent: prioritize strictness and auditability.

Defaults:
- Edge compatibility: require explicit adapter nodes (no implicit resizing).

Notes:
- This tier is intended for deterministic, reviewable pipelines where graph correctness is enforced.
