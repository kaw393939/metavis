# MetaVisCore - Specification

## Goals
1.  Provide the shared types and utilities for the entire system.
2.  Ensure thread-safety and `Sendable` compliance for all core types.

## Requirements
- **RenderManifest**: Must be fully `Codable` and versioned.
- **Logging**: Provide a unified logging interface (e.g., `OSLog`).
- **Configuration**: Centralized configuration management.
