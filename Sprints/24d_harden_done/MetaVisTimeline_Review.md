# MetaVisTimeline Code Review

**Date:** 2025-12-21
**Reviewer:** Antigravity Agent
**Module:** `MetaVisTimeline`

## 1. Executive Summary

`MetaVisTimeline` serves as the serializable data model for the editing session. It definitions the structure of a Project: `Timeline` -> `Tracks` -> `Clips` -> `AssetReference`.

**Strengths:**
- **Purity:** The data model is entirely composed of Value Types (`struct`, `enum`) that are `Codable`, `Sendable`, and `Equatable`. This is perfect for the unidirectional data flow architecture seen in `MetaVisSession`.
- **Composition:** Effects are modeled as a linear list of `FeatureApplication` on the `Clip`, which aligns with the node-graph compilation strategy in `MetaVisSimulation`.
- **Transition Model:** Unified `Transition` model supporting Cuts, Crossfades, Dips, and Wipes with easing curves.

**Critical Gaps:**
- **Track Layout:** Tracks are simple lists of clips. There is no explicit "Lane" or "Layer" handling for overlapping clips within a track (A/B roll), although the Compiler seems to handle overlaps by sorting.
- **Asset ID Resolution:** `AssetReference` relies on string-based `sourceFn` (URI). Resolving these URIs to actual disk paths is left to the upper layers, which is clean but requires strict discipline.

---

## 2. Detailed Findings

### 2.1 The Data Hierarchy
- **Timeline:** Root object. Contains `tracks` and `duration`.
- **Track:** Named collection of clips. Has a `TrackKind` (video, audio, data).
- **Clip:** The atomic editing unit. Maps a `Time` range in the timeline to a `Time` range in the source Asset.
- **AssetReference:** A lightweight handle (UUID + String URI) to media.

### 2.2 Transitions (`Transition.swift`)
- **Type Safety:** `TransitionType` enum ensures validity (Cut, Crossfade, Dip, Wipe).
- **Easing:** Built-in `EasingCurve` (linear, easeIn/Out) allows for smooth animation.
- **Model:** Transition ownership is on the *Clip* (`transitionIn`, `transitionOut`). This is simpler than having separate "Transition Objects" on the timeline, but makes asymmetric transitions (e.g. 1s out, 2s in) slightly harder to reason about if they overlap weirdly.

---

## 3. Recommendations

1.  **Strict Track Overlaps:** Enforce a "No Overlap" invariant for clips *on the same track* unless you explicitly support multi-lane tracks. The current model allows overlaps (which the compiler handles), but this might be confusing for UI rendering.
2.  **Asset Protocols:** Consider extracting a `AssetResolvable` protocol to decouple the String URI from the actual resolution logic, making unit testing easier.
