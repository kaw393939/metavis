import Foundation
import AVFoundation

import MetaVisSession
import MetaVisExport
import MetaVisSimulation
import MetaVisCore

enum ExportDemosCommand {
    struct Options: Sendable {
        var outputDirURL: URL
        var allowLarge: Bool

        init(outputDirURL: URL, allowLarge: Bool) {
            self.outputDirURL = outputDirURL
            self.allowLarge = allowLarge
        }
    }

    static func run(args: [String]) async throws {
        let options = try parse(args: args)
        try await run(options: options)
    }

    static func run(options: Options) async throws {
        let fm = FileManager.default
        try fm.createDirectory(at: options.outputDirURL, withIntermediateDirectories: true)

        let engine = try MetalSimulationEngine()
        let exporter = VideoExporter(engine: engine)
        let quality = QualityProfile(name: "Review1080", fidelity: .high, resolutionHeight: 1080, colorDepth: 10)

        let demos: [(id: String, name: String, make: () -> any ProjectRecipe, isPotentiallyLarge: Bool)] = [
            (
                id: DemoRecipes.KeithTalkEditingDemo().id,
                name: DemoRecipes.KeithTalkEditingDemo().name,
                make: { DemoRecipes.KeithTalkEditingDemo() },
                isPotentiallyLarge: true
            ),
            (
                id: DemoRecipes.BrollMontageDemo().id,
                name: DemoRecipes.BrollMontageDemo().name,
                make: { DemoRecipes.BrollMontageDemo() },
                isPotentiallyLarge: false
            ),
            (
                id: DemoRecipes.ProceduralValidationDemo().id,
                name: DemoRecipes.ProceduralValidationDemo().name,
                make: { DemoRecipes.ProceduralValidationDemo() },
                isPotentiallyLarge: false
            ),
            (
                id: DemoRecipes.ColorCapabilitiesDemo().id,
                name: DemoRecipes.ColorCapabilitiesDemo().name,
                make: { DemoRecipes.ColorCapabilitiesDemo() },
                isPotentiallyLarge: false
            ),
            (
                id: DemoRecipes.AudioCleanwaterDemo().id,
                name: DemoRecipes.AudioCleanwaterDemo().name,
                make: { DemoRecipes.AudioCleanwaterDemo() },
                isPotentiallyLarge: false
            )
        ]

        var wrote: [(String, URL)] = []
        wrote.reserveCapacity(demos.count)

        for demo in demos {
            if demo.isPotentiallyLarge && !options.allowLarge {
                print("⏭️  Skipping potentially-large demo: \(demo.name) (pass --allow-large)")
                continue
            }

            let safeBase = sanitizeFileBase(demo.name)
            let outURL = options.outputDirURL.appendingPathComponent("\(safeBase).mov")

            // Remove existing file to keep outputs deterministic and easy to find.
            if fm.fileExists(atPath: outURL.path) {
                try fm.removeItem(at: outURL)
            }

            print("⏳ Exporting demo: \(demo.name)")
            print("   → \(outURL.path)")

            let session = ProjectSession(recipe: demo.make())
            try await session.exportMovie(
                using: exporter,
                to: outURL,
                quality: quality,
                frameRate: 24,
                codec: .hevc,
                audioPolicy: .auto
            )

            wrote.append((demo.name, outURL))
            print("✅ Exported: \(demo.name)")
        }

        if wrote.isEmpty {
            print("No demos exported.")
        } else {
            print("\n📦 Demo exports written:")
            for (name, url) in wrote {
                print("- \(name): \(url.path)")
            }
        }
    }

    private static func parse(args: [String]) throws -> Options {
        func usage(_ message: String) -> NSError {
            NSError(domain: "MetaVisLab", code: 200, userInfo: [NSLocalizedDescriptionKey: "\(message)\n\n" + MetaVisLabHelp.text])
        }

        var outPath: String?
        var allowLarge = false

        var i = 0
        while i < args.count {
            let a = args[i]
            switch a {
            case "--out":
                i += 1
                guard i < args.count else { throw usage("Missing value for --out") }
                outPath = args[i]
            case "--allow-large":
                allowLarge = true
            case "--help", "-h":
                throw usage("")
            default:
                throw usage("Unknown arg: \(a)")
            }
            i += 1
        }

        let outputURL: URL
        if let outPath {
            outputURL = URL(fileURLWithPath: outPath)
        } else {
            outputURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("test_outputs")
                .appendingPathComponent("project_exports")
        }

        return Options(outputDirURL: outputURL, allowLarge: allowLarge)
    }

    private static func sanitizeFileBase(_ name: String) -> String {
        let lowered = name.lowercased()
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789_- ")
        let cleaned = String(lowered.map { allowed.contains($0) ? $0 : " " })
        let collapsed = cleaned.split(separator: " ").joined(separator: "_")
        return collapsed.isEmpty ? "demo" : collapsed
    }
}
