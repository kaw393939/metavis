# Sprint 08: Primitive Extraction

## 1. Objective
Extract `Time` and `Rational` from `MetaVisCore` into a new `MetaVisPrimitives` module.

## 2. Scope
*   **Target Modules**: `MetaVisCore`, `MetaVisPrimitives` (New)

## 3. Acceptance Criteria
1.  **Decoupling**: `MetaVisCore` imports `MetaVisPrimitives`.
2.  **No Regression**: All time math remains correct.

## 4. Implementation Strategy
*   Create new Package target.
*   Move `Time.swift`, `Rational.swift`, `StableHash.swift`.
*   Update imports everywhere.
