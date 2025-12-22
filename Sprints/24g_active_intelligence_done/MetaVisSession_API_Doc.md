# MetaVisSession API Documentation

`MetaVisSession` manages the lifecycle of an open editing project.

## Core Components

### `ProjectSession`
The main controller (Actor).

```swift
// 1. Create a session from a recipe
let recipe = StandardRecipes.SmokeTest2s()
let session = ProjectSession(recipe: recipe)

// 2. Dispatch edits
await session.dispatch(.setProjectName("My Cool Video"))

// 3. Undo/Redo
await session.undo()
await session.redo()
```

### `ProjectState`
The value type representing the entire document.
```swift
struct ProjectState {
    var timeline: Timeline
    var config: ProjectConfig
    var visualContext: SemanticFrame? // The "AI's Eye" view of the current frame
}
```

## AI & Intelligence

### Natural Language Editing
Pass natural language string commands to the session. It uses the configured `LocalLLMService` to interpret them.

```swift
let intent = try await session.processCommand("Ripple delete the second clip")
if let intent {
    // Apply it
    await session.applyIntent(intent)
}
```

## IO & Export

### Persistence
Load and save projects to disk.
```swift
try ProjectPersistence.save(state: session.state, to: url)
let doc = try ProjectPersistence.load(from: url)
```

### Export
Run an export job with full governance checks.
```swift
try await session.exportMovie(
    using: MetaVisExport.AVFoundationExporter(),
    to: outputURL,
    quality: .proRes422HQ,
    frameRate: 24
)
```
