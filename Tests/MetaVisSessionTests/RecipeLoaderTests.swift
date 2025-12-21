import XCTest
import MetaVisCore
import MetaVisSession

final class RecipeLoaderTests: XCTestCase {

    func testWriteThenLoadDefinitionRoundTrips() throws {
        let state = StandardRecipes.SmokeTest2s().makeInitialState()
        let def = JSONProjectRecipeDefinition(
            schemaVersion: 1,
            id: "com.metavis.recipe.json.smoke_test_2s",
            name: "JSON Smoke Test (2s)",
            projectState: state
        )

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("recipe.v1.json")

        try RecipeLoader.writeDefinition(def, to: url)
        let loaded = try RecipeLoader.loadDefinition(from: url)

        XCTAssertEqual(loaded, def)
    }

    func testWriteDefinitionIsDeterministic() throws {
        let state = StandardRecipes.SmokeTest2s().makeInitialState()
        let def = JSONProjectRecipeDefinition(
            schemaVersion: 1,
            id: "com.metavis.recipe.json.deterministic",
            name: "Deterministic JSON",
            projectState: state
        )

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let urlA = dir.appendingPathComponent("a.json")
        let urlB = dir.appendingPathComponent("b.json")

        try RecipeLoader.writeDefinition(def, to: urlA)
        try RecipeLoader.writeDefinition(def, to: urlB)

        let dataA = try Data(contentsOf: urlA)
        let dataB = try Data(contentsOf: urlB)
        XCTAssertEqual(dataA, dataB)
    }

    func testLoadDefinitionRejectsUnsupportedSchemaVersion() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("bad.json")

        // Construct a valid payload and only vary schemaVersion.
        // This keeps the test resilient to Codable shape changes (e.g. Time encoding).
        let def = JSONProjectRecipeDefinition(
            schemaVersion: 999,
            id: "x",
            name: "Bad",
            projectState: ProjectState()
        )
        try RecipeLoader.writeDefinition(def, to: url)

        XCTAssertThrowsError(try RecipeLoader.loadDefinition(from: url)) { err in
            XCTAssertEqual(err as? RecipeLoaderError, .unsupportedSchemaVersion(999))
        }
    }

    func testProjectSessionInitFromRecipeURLUsesLoadedState() async throws {
        let recipe = StandardRecipes.SmokeTest2s()
        let state = recipe.makeInitialState()

        let def = JSONProjectRecipeDefinition(
            schemaVersion: 1,
            id: recipe.id,
            name: recipe.name,
            projectState: state
        )

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("recipe.v1.json")
        try RecipeLoader.writeDefinition(def, to: url)

        let session = try ProjectSession.load(recipeURL: url)
        let loadedState = await session.state

        XCTAssertEqual(loadedState.config.name, recipe.name)
        XCTAssertEqual(loadedState.timeline.duration.seconds, state.timeline.duration.seconds, accuracy: 0.0001)
    }
}
