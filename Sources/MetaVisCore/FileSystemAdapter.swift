import Foundation

public protocol FileSystemAdapter: Sendable {
    func createDirectory(at url: URL, withIntermediateDirectories: Bool) throws
    func write(_ data: Data, to url: URL) throws
}

public struct DiskFileSystemAdapter: FileSystemAdapter {
    public init() {}

    public func createDirectory(at url: URL, withIntermediateDirectories: Bool) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: withIntermediateDirectories)
    }

    public func write(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: [.atomic])
    }
}

public final class InMemoryFileSystemAdapter: FileSystemAdapter, @unchecked Sendable {
    private let lock = NSLock()
    private var directories: Set<URL> = []
    private var files: [URL: Data] = [:]

    public init() {}

    public func createDirectory(at url: URL, withIntermediateDirectories: Bool) throws {
        lock.lock()
        defer { lock.unlock() }
        directories.insert(url)
    }

    public func write(_ data: Data, to url: URL) throws {
        lock.lock()
        defer { lock.unlock() }
        files[url] = data
    }

    public func read(_ url: URL) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return files[url]
    }

    public func containsFile(_ url: URL) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return files[url] != nil
    }
}
