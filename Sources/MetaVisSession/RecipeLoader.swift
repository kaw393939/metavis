import Foundation
import MetaVisCore

public enum RecipeLoaderError: Error, LocalizedError, Sendable, Equatable {
    case decodeFailed
    case unsupportedSchemaVersion(Int)

    public var errorDescription: String? {
        switch self {
        case .decodeFailed:
            return "Failed to decode recipe JSON"
        case .unsupportedSchemaVersion(let v):
            return "Unsupported recipe schemaVersion: \(v)"
        }
    }
}

public struct JSONProjectRecipeDefinition: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var id: String
    public var name: String
    public var projectState: ProjectState

    public init(schemaVersion: Int = 1, id: String, name: String, projectState: ProjectState) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.name = name
        self.projectState = projectState
    }
}

private struct LoadedProjectRecipe: ProjectRecipe {
    let id: String
    let name: String
    let state: ProjectState

    func makeInitialState() -> ProjectState {
        state
    }
}

public enum RecipeLoader {

    public static func loadDefinition(from url: URL) throws -> JSONProjectRecipeDefinition {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        guard let def = try? decoder.decode(JSONProjectRecipeDefinition.self, from: data) else {
            throw RecipeLoaderError.decodeFailed
        }
        guard def.schemaVersion == 1 else {
            throw RecipeLoaderError.unsupportedSchemaVersion(def.schemaVersion)
        }
        return def
    }

    public static func loadRecipe(from url: URL) throws -> any ProjectRecipe {
        let def = try loadDefinition(from: url)
        return LoadedProjectRecipe(id: def.id, name: def.name, state: def.projectState)
    }

    public static func writeDefinition(_ def: JSONProjectRecipeDefinition, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(def)
        try data.write(to: url, options: [.atomic])
    }
}

public extension ProjectSession {
    static func load(
        recipeURL: URL,
        entitlements: EntitlementManager = EntitlementManager(),
        trace: any TraceSink = NoOpTraceSink()
    ) throws -> ProjectSession {
        let recipe = try RecipeLoader.loadRecipe(from: recipeURL)
        return ProjectSession(recipe: recipe, entitlements: entitlements, trace: trace)
    }
}
