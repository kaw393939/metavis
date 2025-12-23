# Search Results: Best source of official ACES 1.3 CTL transforms RRT and ODT files in aces-dev

**Date:** 2025-12-23 04:23:25

## Answer

Short answer: use the aces-core repo (this is the renamed, canonical successor of aces-dev) at the ACES 1.3 tag.

What to pull
- RRT CTL: in transforms/ctl/rrt/ at tag v1.3 (or v1.3.1). ([github.com](https://github.com/aces-aswf/aces-core/tags))
- ODT CTLs: in transforms/ctl/odt/ at tag v1.3 (or v1.3.1). ([github.com](https://github.com/aces-aswf/aces-core/tags))

Why this is the right place
- The aces repo explains that the pre‑2.0 aces-dev history was relabeled as aces-core; so tags like v1.3 in aces-core are the official ACES 1.x sources. ([github.com](https://github.com/ampas/aces))
- ACES 1.3 was a minor release that did not change the RRT (only bug fixes/formatting), so the RRT/ODT CTLs at the 1.3 tag are the authoritative files. ([community.acescentral.com](https://community.acescentral.com/t/aces-1-3-now-available/3739?utm_source=openai))

Notes
- Tags available include v1.3 (April 30, 2021) and v1.3.1 (Dec 20, 2024). If you want the latest 1.3 bugfix snapshot, use v1.3.1; if you need the original 1.3 as released, use v1.3. ([github.com](https://github.com/aces-aswf/aces-core/tags))

If you prefer an OCIO config that auto-discovers these CTLs, see OpenColorIO-Config-ACES, which generates configs directly from the aces-dev/aces-core CTL reference implementation. ([github.com](https://github.com/AcademySoftwareFoundation/OpenColorIO-Config-ACES?utm_source=openai))
