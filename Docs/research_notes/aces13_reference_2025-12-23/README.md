# ACES 1.3 reference resources (2025-12-23)

This folder captures reproducible research outputs (via `eai search`) to support a **certification-grade** ACES 1.3 validator path in MetaVis.

## What we need (for Studio-grade validation)

MetaVis currently runs in **linear ACEScg** and appends a terminal **ODT** kernel. For *reference* validation we need the normative transforms for:

- **RRT** (Reference Rendering Transform)
- **ODT(s)** (Output Device Transforms)
  - SDR: **Rec.709 100 nits dim surround** (BT.1886 / 2.4-ish)
  - HDR: **Rec.2020 PQ 1000 nits / 15 nits mid-gray** (ST 2084)

Those exist as CTL in the ACES 1.x codebase, and are also surfaced in official ACES OCIO configs.

## Recommended authoritative sources

### 1) ACES CTL (RRT + ODT)

- Repo (ACES 1.x history via tags): https://github.com/ampas/aces-core (or ASWF mirror tags)
- Target tag: **v1.3** (or v1.3.x)
- Key CTL file names to vendor/reference:
  - `RRT.ctl` (typically under `transforms/ctl/rrt/`)
  - `ODT.Academy.Rec709_100nits_dim.ctl` (typically under `transforms/ctl/odt/rec709/`)
  - `ODT.Academy.Rec2020_1000nits_15nits_ST2084.ctl` (typically under `transforms/ctl/odt/rec2020/`)

If we can execute CTL (e.g., `ctlrender`) we can produce goldens directly from these.

### 2) Official ACES OCIO configs (preferred practical path)

- Repo: https://github.com/AcademySoftwareFoundation/OpenColorIO-Config-ACES
- Releases: https://github.com/AcademySoftwareFoundation/OpenColorIO-Config-ACES/releases

The releases include prebuilt ACES 1.3 configs (CG + Studio) for OCIO v2, which provide a stable, well-tested way to evaluate RRT+ODT.

## Intended use in MetaVis

- Use the OCIO config / CTL reference to **bake a 3D LUT** (Rec.709 first, PQ1000 next).
- Apply that LUT using the existing GPU path (`lut_apply_3d`) for **Studio tier** outputs.
- Validate with deterministic generators (`ligm://video/macbeth`) + ΔE tracking against the reference output.

## Raw evidence

This folder contains `*.json` outputs from `eai search` for:
- RRT/ODT CTL names
- OCIO config sources/releases
- LUT baking tooling pointers (e.g., `ociobakelut`)
