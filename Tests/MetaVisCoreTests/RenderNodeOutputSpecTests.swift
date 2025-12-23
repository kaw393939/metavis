import XCTest
@testable import MetaVisCore

final class RenderNodeOutputSpecTests: XCTestCase {

    func test_resolvedOutputSize_defaultsToBaseSize() {
        let node = RenderNode(name: "Test", shader: "noop")
        let size = node.resolvedOutputSize(baseWidth: 1920, baseHeight: 1080)
        XCTAssertEqual(size.width, 1920)
        XCTAssertEqual(size.height, 1080)
    }

    func test_resolvedOutputPixelFormat_defaultsToRGBA16Float() {
        let node = RenderNode(name: "Test", shader: "noop")
        XCTAssertEqual(node.resolvedOutputPixelFormat(), .rgba16Float)
    }

    func test_resolvedOutputPixelFormat_usesSpecifiedValue() {
        let node = RenderNode(
            name: "Mask",
            shader: "noop",
            output: .init(resolution: .full, pixelFormat: .r8Unorm)
        )
        XCTAssertEqual(node.resolvedOutputPixelFormat(), .r8Unorm)
    }

    func test_resolvedOutputSize_half() {
        let node = RenderNode(
            name: "Half",
            shader: "noop",
            output: .init(resolution: .half)
        )
        let size = node.resolvedOutputSize(baseWidth: 1920, baseHeight: 1080)
        XCTAssertEqual(size.width, 960)
        XCTAssertEqual(size.height, 540)
    }

    func test_resolvedOutputSize_quarter() {
        let node = RenderNode(
            name: "Quarter",
            shader: "noop",
            output: .init(resolution: .quarter)
        )
        let size = node.resolvedOutputSize(baseWidth: 1920, baseHeight: 1080)
        XCTAssertEqual(size.width, 480)
        XCTAssertEqual(size.height, 270)
    }

    func test_resolvedOutputSize_fixed() {
        let node = RenderNode(
            name: "Fixed",
            shader: "noop",
            output: .init(resolution: .fixed, fixedWidth: 256, fixedHeight: 128)
        )
        let size = node.resolvedOutputSize(baseWidth: 1920, baseHeight: 1080)
        XCTAssertEqual(size.width, 256)
        XCTAssertEqual(size.height, 128)
    }

    func test_resolvedOutputSize_neverReturnsZero() {
        let node = RenderNode(
            name: "FixedZero",
            shader: "noop",
            output: .init(resolution: .fixed, fixedWidth: 0, fixedHeight: 0)
        )
        let size = node.resolvedOutputSize(baseWidth: 0, baseHeight: 0)
        XCTAssertGreaterThanOrEqual(size.width, 1)
        XCTAssertGreaterThanOrEqual(size.height, 1)
    }
}
