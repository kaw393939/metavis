# Sprint 03: Shader Safety

## 1. Objective
Eliminate stringly-typed access to Metal shaders in `MetaVisGraphics`. Currently, renaming a `.metal` kernel works but crashes the app at runtime when Swift code looks for the old string name.

## 2. Scope
*   **Target Modules**: `MetaVisGraphics`
*   **Key Files**: `GraphicsBundleHelper.swift`

## 3. Acceptance Criteria
1.  **Type Safety**: Access shaders via static constants (e.g. `Shaders.Color.aces_to_rec709`) instead of raw strings.
2.  **Validation**: A unit test must fail if a declared constant does not match a kernel in `default.metallib`.

## 4. Implementation Strategy
*   Create a script or manual struct that maps strings to constants.
*   Add a test case that loads the library and iterates all constants to verify existence.

## 5. Artifacts
*   [TDD Plan](./tdd_plan.md)
