import XCTest
import MetaVisCore
import MetaVisTimeline
@testable import MetaVisSession

final class ProjectPersistenceTests: XCTestCase {

    func testSaveLoadRoundTripProjectDocumentV1() async throws {
        let recipe = StandardRecipes.SmokeTest2s()
        let session = ProjectSession(recipe: recipe)

        let tmp = FileManager.default.temporaryDirectory
        let url = tmp.appendingPathComponent("metavis_project_roundtrip.json")

        let createdAt = "2025-12-19T00:00:00.000Z"
        let updatedAt = "2025-12-19T00:00:01.000Z"

        try await session.saveProject(
            to: url,
            recipeID: recipe.id,
            createdAt: createdAt,
            updatedAt: updatedAt,
            includeVisualContext: false
        )

        let doc = try ProjectPersistence.load(from: url)
        XCTAssertEqual(doc.schemaVersion, 1)
        XCTAssertEqual(doc.createdAt, createdAt)
        XCTAssertEqual(doc.updatedAt, updatedAt)
        XCTAssertEqual(doc.recipeID, recipe.id)

        // visualContext should be omitted by default
        XCTAssertNil(doc.state.visualContext)

        let loadedSession = try ProjectSession.loadProject(from: url)
        let originalState = await session.state
        let loadedState = await loadedSession.state

        XCTAssertEqual(loadedState, originalState)
    }

    func testProjectDocumentSaveIsDeterministicGivenFixedTimestamps() async throws {
        let recipe = StandardRecipes.SmokeTest2s()
        let session = ProjectSession(recipe: recipe)

        let tmp = FileManager.default.temporaryDirectory
        let url1 = tmp.appendingPathComponent("metavis_project_deterministic_1.json")
        let url2 = tmp.appendingPathComponent("metavis_project_deterministic_2.json")

        let createdAt = "2025-12-19T00:00:00.000Z"
        let updatedAt = "2025-12-19T00:00:00.000Z"

        try await session.saveProject(
            to: url1,
            recipeID: recipe.id,
            createdAt: createdAt,
            updatedAt: updatedAt,
            includeVisualContext: false
        )

        try await session.saveProject(
            to: url2,
            recipeID: recipe.id,
            createdAt: createdAt,
            updatedAt: updatedAt,
            includeVisualContext: false
        )

        let d1 = try Data(contentsOf: url1)
        let d2 = try Data(contentsOf: url2)
        XCTAssertEqual(d1, d2)
    }
}
