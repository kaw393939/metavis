import XCTest
import MetaVisPerception

final class PerceptionDeviceGroupTests: XCTestCase {

    actor Recorder {
        private(set) var events: [String] = []
        func add(_ s: String) { events.append(s) }
    }

    actor DummyDevice: PerceptionDevice {
        typealias Input = Int
        typealias Output = Int

        let name: String
        let recorder: Recorder
        private(set) var warmed: Int = 0
        private(set) var cooled: Int = 0

        init(name: String, recorder: Recorder) {
            self.name = name
            self.recorder = recorder
        }

        func warmUp() async throws {
            warmed += 1
            await recorder.add("warmUp:\(name)")
        }

        func coolDown() async {
            cooled += 1
            await recorder.add("coolDown:\(name)")
        }

        func warmedCount() async -> Int { warmed }
        func cooledCount() async -> Int { cooled }

        func infer(_ input: Int) async throws -> Int {
            input
        }
    }

    func test_group_warmup_is_in_order_and_cooldown_is_reverse_order() async throws {
        let recorder = Recorder()
        let a = DummyDevice(name: "A", recorder: recorder)
        let b = DummyDevice(name: "B", recorder: recorder)
        let c = DummyDevice(name: "C", recorder: recorder)

        let devices: [AnyPerceptionDeviceLifecycle] = [
            .init(a, name: "A"),
            .init(b, name: "B"),
            .init(c, name: "C")
        ]

        try await PerceptionDeviceGroupV1.warmUpAll(devices)
        await PerceptionDeviceGroupV1.coolDownAll(devices)

        let events = await recorder.events
        XCTAssertEqual(events, [
            "warmUp:A",
            "warmUp:B",
            "warmUp:C",
            "coolDown:C",
            "coolDown:B",
            "coolDown:A"
        ])

        let warmedA = await a.warmedCount()
        let warmedB = await b.warmedCount()
        let warmedC = await c.warmedCount()

        let cooledA = await a.cooledCount()
        let cooledB = await b.cooledCount()
        let cooledC = await c.cooledCount()

        XCTAssertEqual(warmedA, 1)
        XCTAssertEqual(warmedB, 1)
        XCTAssertEqual(warmedC, 1)

        XCTAssertEqual(cooledA, 1)
        XCTAssertEqual(cooledB, 1)
        XCTAssertEqual(cooledC, 1)
    }

    func test_withWarmedUp_always_cools_down_when_operation_throws() async {
        let recorder = Recorder()
        let a = DummyDevice(name: "A", recorder: recorder)
        let b = DummyDevice(name: "B", recorder: recorder)
        let devices: [AnyPerceptionDeviceLifecycle] = [
            .init(a, name: "A"),
            .init(b, name: "B")
        ]

        do {
            _ = try await PerceptionDeviceGroupV1.withWarmedUp(devices) {
                struct Boom: Error {}
                throw Boom()
            }
            XCTFail("Expected throw")
        } catch {
            // expected
        }

        let events = await recorder.events
        XCTAssertEqual(events, [
            "warmUp:A",
            "warmUp:B",
            "coolDown:B",
            "coolDown:A"
        ])
    }
}
