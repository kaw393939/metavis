# TDD Plan: Sprint 03

## New Tests
1.  **Shader Existence Test**:
    *   Load `GraphicsBundleHelper.bundle`.
    *   Instantiate `MTLLibrary`.
    *   Iterate `Shaders.allCases`.
    *   **Assert**: `library.makeFunction(name: shader)` is not nil.

## Test Command
```bash
swift test --filter MetaVisGraphicsTests
```
