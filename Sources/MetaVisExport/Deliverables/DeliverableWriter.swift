import Foundation

public enum DeliverableWriter {
    /// Writes a deliverable bundle atomically by staging into a temporary directory and then moving into place.
    ///
    /// The `populate` closure must write `video.mov` into the provided staging directory.
    /// This function writes `deliverable.json` and finalizes the bundle.
    public static func writeBundle(
        at bundleURL: URL,
        populate: (URL) async throws -> DeliverableManifest
    ) async throws -> DeliverableManifest {
        let fm = FileManager.default

        let parent = bundleURL.deletingLastPathComponent()
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)

        let stagingName = ".\(bundleURL.lastPathComponent).staging-\(UUID().uuidString)"
        let stagingURL = parent.appendingPathComponent(stagingName, isDirectory: true)

        // Clean up any leftovers just in case.
        try? fm.removeItem(at: stagingURL)

        do {
            try fm.createDirectory(at: stagingURL, withIntermediateDirectories: true)

            let manifest = try await populate(stagingURL)

            let manifestURL = stagingURL.appendingPathComponent("deliverable.json")
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(manifest)
            try data.write(to: manifestURL, options: [.atomic])

            if fm.fileExists(atPath: bundleURL.path) {
                try fm.removeItem(at: bundleURL)
            }

            try fm.moveItem(at: stagingURL, to: bundleURL)
            return manifest
        } catch {
            try? fm.removeItem(at: stagingURL)
            throw error
        }
    }
}
