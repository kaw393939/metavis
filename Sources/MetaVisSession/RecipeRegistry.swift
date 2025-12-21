import Foundation
import MetaVisCore

public enum RecipeRegistryError: Error, LocalizedError, Sendable, Equatable {
    case unknownRecipeID(String)

    public var errorDescription: String? {
        switch self {
        case .unknownRecipeID(let id):
            return "Unknown recipe id: \(id)"
        }
    }
}

/// Central registry to look up project recipes by string id.
public enum RecipeRegistry {

    public static var allRecipeIDs: [String] {
        [
            StandardRecipes.SmokeTest2s().id,
            StandardRecipes.GodTest20s().id,
            DemoRecipes.KeithTalkEditingDemo().id,
            DemoRecipes.BrollMontageDemo().id,
            DemoRecipes.ProceduralValidationDemo().id,
            DemoRecipes.AudioCleanwaterDemo().id,
            DemoRecipes.ColorCapabilitiesDemo().id
        ]
    }

    public static func makeRecipe(id: String) -> (any ProjectRecipe)? {
        switch id {
        case StandardRecipes.SmokeTest2s().id:
            return StandardRecipes.SmokeTest2s()
        case StandardRecipes.GodTest20s().id:
            return StandardRecipes.GodTest20s()
        case DemoRecipes.KeithTalkEditingDemo().id:
            return DemoRecipes.KeithTalkEditingDemo()
        case DemoRecipes.BrollMontageDemo().id:
            return DemoRecipes.BrollMontageDemo()
        case DemoRecipes.ProceduralValidationDemo().id:
            return DemoRecipes.ProceduralValidationDemo()
        case DemoRecipes.AudioCleanwaterDemo().id:
            return DemoRecipes.AudioCleanwaterDemo()
        case DemoRecipes.ColorCapabilitiesDemo().id:
            return DemoRecipes.ColorCapabilitiesDemo()
        default:
            return nil
        }
    }

    public static func makeInitialState(recipeID: String) -> ProjectState? {
        makeRecipe(id: recipeID)?.makeInitialState()
    }
}

public extension ProjectSession {
    init(
        recipeID: String,
        entitlements: EntitlementManager = EntitlementManager(),
        trace: any TraceSink = NoOpTraceSink()
    ) throws {
        guard let state = RecipeRegistry.makeInitialState(recipeID: recipeID) else {
            throw RecipeRegistryError.unknownRecipeID(recipeID)
        }
        self.init(initialState: state, entitlements: entitlements, trace: trace)
    }

    init(
        projectType: ProjectType,
        entitlements: EntitlementManager = EntitlementManager(),
        trace: any TraceSink = NoOpTraceSink()
    ) throws {
        try self.init(recipeID: projectType.defaultRecipeID, entitlements: entitlements, trace: trace)
    }
}
