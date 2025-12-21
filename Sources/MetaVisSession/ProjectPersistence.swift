import Foundation
import MetaVisCore

/// Stable, on-disk project persistence.
///
/// v1 goal: persist the editable `ProjectState` (timeline + config) deterministically.
/// Non-goal: persist undo/redo stacks.
public struct ProjectDocumentV1: Codable, Sendable, Equatable {
    public var schemaVersion: Int

    /// ISO-8601 string (UTC). Stored as String to keep encoding deterministic.
    public var createdAt: String

    /// ISO-8601 string (UTC). Stored as String to keep encoding deterministic.
    public var updatedAt: String

    /// Optional origin recipe id if the project was created from a recipe.
    public var recipeID: String?

    public var state: ProjectState

    public init(
        schemaVersion: Int = 1,
        createdAt: String,
        updatedAt: String,
        recipeID: String? = nil,
        state: ProjectState
    ) {
        self.schemaVersion = schemaVersion
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.recipeID = recipeID
        self.state = state
    }
}

public enum ProjectPersistence {

    public static func nowISOString() -> String {
        let f = ISO8601DateFormatter()
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: Date())
    }

    public static func save(
        state: ProjectState,
        to url: URL,
        recipeID: String? = nil,
        createdAt: String? = nil,
        updatedAt: String? = nil,
        includeVisualContext: Bool = false
    ) throws {
        var stableState = state
        if !includeVisualContext {
            stableState.visualContext = nil
        }

        let created = createdAt ?? nowISOString()
        let updated = updatedAt ?? created

        let doc = ProjectDocumentV1(
            createdAt: created,
            updatedAt: updated,
            recipeID: recipeID,
            state: stableState
        )

        // Use deterministic encoding (sorted keys, pretty printed) for easy diffing.
        try JSONWriting.write(doc, to: url)
    }

    public static func load(from url: URL) throws -> ProjectDocumentV1 {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        return try decoder.decode(ProjectDocumentV1.self, from: data)
    }
}
