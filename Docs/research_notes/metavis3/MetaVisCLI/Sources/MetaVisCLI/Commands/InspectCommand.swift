import Foundation
import ArgumentParser
import MetaVisCore

struct InspectCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "inspect",
        abstract: "Inspect FITS files statistics."
    )

    func run() throws {
        let fileManager = FileManager.default
        let assetsPath = "assets"

        guard let files = try? fileManager.contentsOfDirectory(atPath: assetsPath) else {
            print("Could not list assets")
            return
        }

        let fitsFiles = files.filter { $0.hasSuffix(".fits") }
        let reader = FITSReader()

        for file in fitsFiles {
            let url = URL(fileURLWithPath: assetsPath).appendingPathComponent(file)
            do {
                let asset = try reader.read(url: url)
                print("File: \(file)")
                print("  Min: \(asset.statistics.min)")
                print("  Max: \(asset.statistics.max)")
                print("  Mean: \(asset.statistics.mean)")
                print("--------------------------------------------------")
            } catch {
                print("Failed to read \(file): \(error)")
            }
        }
    }
}
