import Foundation

/// Defines compliant filesystem locations for CLI and batch pipelines.
///
/// This avoids hardcoded absolute paths and centralizes temp/document roots.
public struct IOContext: Sendable {
    public let processTemp: URL
    public let documents: URL

    public init(processTemp: URL, documents: URL) {
        self.processTemp = processTemp
        self.documents = documents
    }

    public static func `default`(fileManager: FileManager = .default) -> IOContext {
        let tempRoot = fileManager.temporaryDirectory
            .appendingPathComponent("metavis", isDirectory: true)

        // For CLI tooling, default documents root to the current working directory.
        // Call sites can override this with an explicit output directory if desired.
        let documentsRoot = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)

        return IOContext(processTemp: tempRoot, documents: documentsRoot)
    }

    public func prepare(fileManager: FileManager = .default) throws {
        try fileManager.createDirectory(at: processTemp, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: documents, withIntermediateDirectories: true)
    }
}
