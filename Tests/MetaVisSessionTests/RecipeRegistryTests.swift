import XCTest
import MetaVisCore
import MetaVisSession

final class RecipeRegistryTests: XCTestCase {

    func testRecipeRegistryKnownRecipesCanBeBuilt() throws {
        for id in RecipeRegistry.allRecipeIDs {
            let recipe = try XCTUnwrap(RecipeRegistry.makeRecipe(id: id), "Missing recipe for id: \(id)")
            XCTAssertEqual(recipe.id, id)
        }
    }

    func testProjectTypeDefaultRecipeIDIsRegistered() {
        for projectType in ProjectType.allCases {
            let id = projectType.defaultRecipeID
            XCTAssertTrue(
                RecipeRegistry.allRecipeIDs.contains(id),
                "Default recipe id for \(projectType) not registered: \(id)"
            )
        }
    }

    func testProjectSessionInitWithRecipeIDUsesRecipeInitialState() async throws {
        let recipe = StandardRecipes.SmokeTest2s()
        let session = try ProjectSession(recipeID: recipe.id)

        let state = await session.state
        XCTAssertEqual(state.config.name, recipe.name)
        XCTAssertEqual(state.timeline.duration.seconds, 2.0, accuracy: 0.0001)
    }
}
