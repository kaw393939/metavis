import XCTest
@testable import MetaVisSimulation

final class FeatureManifestPassesCodableTests: XCTestCase {
    func test_decode_with_passes() throws {
        let json = """
        {
          \"id\": \"blurGaussian\",
          \"version\": \"1.0.0\",
          \"name\": \"Gaussian Blur\",
          \"category\": \"blur\",
          \"inputs\": [
            { \"name\": \"source\", \"type\": \"image\" }
          ],
          \"parameters\": [
            { \"type\": \"float\", \"name\": \"radius\", \"min\": 0.0, \"max\": 64.0, \"defaultValue\": 4.0 }
          ],
          \"kernelName\": \"fx_blur_v\",
          \"passes\": [
            {
              \"logicalName\": \"blur_h\",
              \"function\": \"fx_blur_h\",
              \"inputs\": [\"source\"],
              \"output\": \"tmp\"
            },
            {
              \"logicalName\": \"blur_v\",
              \"function\": \"fx_blur_v\",
              \"inputs\": [\"tmp\"],
              \"output\": \"output\"
            }
          ]
        }
        """

        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(FeatureManifest.self, from: data)
        XCTAssertEqual(decoded.passes?.count, 2)
        XCTAssertEqual(decoded.passes?.first?.output, "tmp")
    }
}
