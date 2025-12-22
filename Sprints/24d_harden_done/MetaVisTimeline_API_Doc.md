# MetaVisTimeline API Documentation

`MetaVisTimeline` provides the value types that describe an editing project.

## Core Data Structures

### `Timeline`
The root document.
```swift
var timeline = Timeline()
timeline.tracks.append(Track(name: "Main Video", kind: .video))
```

### `Clip`
A segment of media.
```swift
let clip = Clip(
    name: "Scene 1",
    asset: AssetReference(sourceFn: "file:///path/to/media.mov"),
    startTime: Time(seconds: 0),
    duration: Time(seconds: 5),
    offset: Time(seconds: 10) // Start reading from 10s mark of source
)
```

### `Transition`
Applied to clip boundaries.
```swift
var clip = ...
clip.transitionIn = .crossfade(duration: Time(seconds: 1.0))
clip.transitionOut = .dipToBlack(duration: Time(seconds: 0.5))
```

### `FeatureApplication`
Effects applied to the clip.
```swift
let effect = FeatureApplication(
    id: "fx_color_grade",
    parameters: ["saturation": .float(1.5)]
)
clip.effects.append(effect)
```
