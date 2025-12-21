# Data Dictionary: Sprint 01

## New Types

### `CowBox<T>`
Wrapper for structural sharing.
*   `value: T`: The underlying value.
*   `access`: accessor that triggers `isKnownUniquelyReferenced` check.

## Modifed Types

### `Timeline`
*   `tracks`: Now `CowBox<[Track]>` instead of `[Track]`.

### `ProjectState`
*   No schema change, but semantic change: extremely cheap to copy.
