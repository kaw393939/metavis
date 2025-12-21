# MetaVisTimeline Assessment

## Initial Assessment
MetaVisTimeline defines the hierarchical data model for a video project. It is decoupled from rendering and playback, focusing solely on the structure of the timeline.

## Capabilities

### 1. Timeline Data Model
- **Structure**: `Timeline` contains a list of `Track`s, which contain a list of `Clip`s.
- **Tracks**: Typed by `TrackKind` (video, audio, data).
- **Clips**: Defined by `AssetReference` (source), `startTime`, `duration`, and `offset` (trim).
- **Serialization**: Fully `Codable` and `Sendable`, making it suitable for saving to disk or sending over network.

### 2. Transition System
- **`Transition`**: First-class support for `in` and `out` transitions per clip.
- **Types**: Cut, Crossfade, Dip to Color, Wipe.
- **Curves**: Easing curves (linear, easeIn/Out).
- **Logic**: `Clip.alpha(at:)` calculates the opacity of a clip based on its transitions and current time, providing a clear contract for the renderer.

### 3. Feature/Effect Abstraction
- **`FeatureApplication`**: Stores effect data (ID + params) without implementing the effect logic.
- **Decoupling**: Allows the timeline to store "intent" (e.g., "Apply color grade") while `MetaVisGraphics` implements the "action".

## Technical Gaps & Debt

### 1. Naive Overlap Logic
- **Constraint**: `Clip.overlaps(with:)` is a simple check. The model allows invalid states (overlapping clips on the same track) which the renderer might handle unpredictably.
- **Missing**: No "Track Topology" enforcement (e.g., preventing gaps or overlaps if desired).

### 2. Limited Composition
- **Constraint**: No nested timelines or "Composition" clips (putting a timeline inside a clip) visible in this module. This limits complex project structures.

## Improvements

1.  **Topology Validation**: Add a `validate()` method to `Timeline` or `Track` to ensure no overlapping clips exist if the track type forbids it.
2.  **Audio Model**: `TrackKind` exists, but audio-specific properties (volume, pan) are likely handled via generic `effects` or strictly in `MetaVisAudio`. Consider first-class audio animation properties if `effects` becomes too heavy.
3.  **Composition Pattern**: Introduce a `TimelineAsset` to allow nesting timelines.
