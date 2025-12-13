import XCTest
import MetaVisCore
import MetaVisPerception

final class PerceptionServiceSafetyTests: XCTestCase {

    private struct DummyRequest: AIInferenceRequest {
        let id = UUID()
        let priority: TaskPriority = .medium
    }

    private struct DummyResult: AIInferenceResult {
        let id = UUID()
        let processingTime: TimeInterval = 0
    }

    func testFaceDetectionInferDoesNotCrash() async {
        let service = FaceDetectionService()
        do {
            let _: DummyResult = try await service.infer(request: DummyRequest())
            XCTFail("Expected infer to throw")
        } catch let err as MetaVisPerceptionError {
            switch err {
            case .unsupportedGenericInfer:
                break
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testFaceIdentityInferDoesNotCrash() async {
        let service = FaceIdentityService()
        do {
            let _: DummyResult = try await service.infer(request: DummyRequest())
            XCTFail("Expected infer to throw")
        } catch let err as MetaVisPerceptionError {
            switch err {
            case .unsupportedGenericInfer:
                break
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testPersonSegmentationInferDoesNotCrash() async {
        let service = PersonSegmentationService()
        do {
            let _: DummyResult = try await service.infer(request: DummyRequest())
            XCTFail("Expected infer to throw")
        } catch let err as MetaVisPerceptionError {
            switch err {
            case .unsupportedGenericInfer:
                break
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
}
