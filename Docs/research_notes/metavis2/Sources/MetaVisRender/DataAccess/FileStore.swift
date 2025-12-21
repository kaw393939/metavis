// FileStore.swift
// MetaVisRender
//
// Created for Sprint 09: Data Access Layer
// File-based storage for binary assets (masks, frames, audio)

import Foundation

// MARK: - FileStore

/// Manages binary assets stored adjacent to video files
/// Structure: {video}.metavis/
///   ├── masks/      - Segmentation masks
///   ├── frames/     - Extracted keyframes
///   ├── audio/      - Extracted/processed audio
///   ├── embeddings/ - Face/voice embeddings
///   └── thumbnails/ - Person thumbnails
public struct FileStore: Sendable {
    
    // MARK: - Properties
    
    /// Base directory for file storage
    public let baseDirectory: URL
    
    /// Original project/video path
    public let projectPath: URL
    
    // MARK: - Subdirectories
    
    /// Directory for segmentation masks
    public var masksDirectory: URL {
        baseDirectory.appendingPathComponent("masks", isDirectory: true)
    }
    
    /// Directory for extracted keyframes
    public var framesDirectory: URL {
        baseDirectory.appendingPathComponent("frames", isDirectory: true)
    }
    
    /// Directory for audio files
    public var audioDirectory: URL {
        baseDirectory.appendingPathComponent("audio", isDirectory: true)
    }
    
    /// Directory for face/voice embeddings
    public var embeddingsDirectory: URL {
        baseDirectory.appendingPathComponent("embeddings", isDirectory: true)
    }
    
    /// Directory for person thumbnails
    public var thumbnailsDirectory: URL {
        baseDirectory.appendingPathComponent("thumbnails", isDirectory: true)
    }
    
    /// Directory for cache files
    public var cacheDirectory: URL {
        baseDirectory.appendingPathComponent("cache", isDirectory: true)
    }
    
    // MARK: - Initialization
    
    /// Initialize file store for a project
    /// - Parameter projectPath: Path to the project directory or video file
    public init(projectPath: URL) {
        self.projectPath = projectPath
        
        // Determine base directory
        if projectPath.hasDirectoryPath || projectPath.pathExtension.isEmpty {
            // Project directory - use it directly
            self.baseDirectory = projectPath
        } else {
            // Video file - create adjacent .metavis directory
            self.baseDirectory = MetavisPaths.adjacentDirectory(for: projectPath)
        }
    }
    
    // MARK: - Directory Management
    
    /// Ensure all directories exist
    public func ensureDirectoriesExist() throws {
        let fm = FileManager.default
        let directories = [
            baseDirectory,
            masksDirectory,
            framesDirectory,
            audioDirectory,
            embeddingsDirectory,
            thumbnailsDirectory,
            cacheDirectory
        ]
        
        for dir in directories {
            if !fm.fileExists(atPath: dir.path) {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            }
        }
    }
    
    /// Get total size of stored files
    public func totalSize() throws -> Int64 {
        let fm = FileManager.default
        guard fm.fileExists(atPath: baseDirectory.path) else { return 0 }
        
        var totalSize: Int64 = 0
        
        if let enumerator = fm.enumerator(at: baseDirectory, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let fileURL as URL in enumerator {
                let fileSize = try fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                totalSize += Int64(fileSize)
            }
        }
        
        return totalSize
    }
    
    /// Clean up all stored files
    public func cleanup() throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: baseDirectory.path) {
            try fm.removeItem(at: baseDirectory)
        }
    }
    
    // MARK: - Mask Operations
    
    /// Save a segmentation mask
    /// - Parameters:
    ///   - data: Mask data (PNG)
    ///   - personID: Person ID this mask belongs to
    ///   - frameTime: Frame time in seconds
    /// - Returns: URL where mask was saved
    @discardableResult
    public func saveMask(_ data: Data, personID: String, frameTime: TimeInterval) throws -> URL {
        try ensureDirectoriesExist()
        
        let filename = "\(personID)_\(formatTime(frameTime)).png"
        let url = masksDirectory.appendingPathComponent(filename)
        
        try data.write(to: url)
        return url
    }
    
    /// Load a segmentation mask
    public func loadMask(personID: String, frameTime: TimeInterval) throws -> Data? {
        let filename = "\(personID)_\(formatTime(frameTime)).png"
        let url = masksDirectory.appendingPathComponent(filename)
        
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }
    
    /// List all masks for a person
    public func masks(for personID: String) throws -> [URL] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: masksDirectory.path) else { return [] }
        
        let contents = try fm.contentsOfDirectory(at: masksDirectory, includingPropertiesForKeys: nil)
        return contents.filter { $0.lastPathComponent.hasPrefix(personID) }
    }
    
    // MARK: - Frame Operations
    
    /// Save a keyframe
    /// - Parameters:
    ///   - data: Frame data (JPEG)
    ///   - frameTime: Frame time in seconds
    /// - Returns: URL where frame was saved
    @discardableResult
    public func saveFrame(_ data: Data, frameTime: TimeInterval) throws -> URL {
        try ensureDirectoriesExist()
        
        let filename = "frame_\(formatTime(frameTime)).jpg"
        let url = framesDirectory.appendingPathComponent(filename)
        
        try data.write(to: url)
        return url
    }
    
    /// Load a keyframe
    public func loadFrame(frameTime: TimeInterval) throws -> Data? {
        let filename = "frame_\(formatTime(frameTime)).jpg"
        let url = framesDirectory.appendingPathComponent(filename)
        
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }
    
    /// Find nearest keyframe to a time
    public func nearestFrame(to time: TimeInterval) throws -> URL? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: framesDirectory.path) else { return nil }
        
        let contents = try fm.contentsOfDirectory(at: framesDirectory, includingPropertiesForKeys: nil)
        let frames = contents.filter { $0.pathExtension == "jpg" }
        
        guard !frames.isEmpty else { return nil }
        
        // Parse time from filename and find nearest
        var nearest: (url: URL, diff: TimeInterval)?
        
        for frame in frames {
            if let frameTime = parseTimeFromFilename(frame.lastPathComponent) {
                let diff = abs(frameTime - time)
                if nearest == nil || diff < nearest!.diff {
                    nearest = (frame, diff)
                }
            }
        }
        
        return nearest?.url
    }
    
    /// List all keyframes
    public func allFrames() throws -> [URL] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: framesDirectory.path) else { return [] }
        
        let contents = try fm.contentsOfDirectory(at: framesDirectory, includingPropertiesForKeys: nil)
        return contents.filter { $0.pathExtension == "jpg" }.sorted {
            $0.lastPathComponent < $1.lastPathComponent
        }
    }
    
    // MARK: - Audio Operations
    
    /// Save extracted audio
    /// - Parameters:
    ///   - data: Audio data
    ///   - name: Audio file name (e.g., "original.wav", "vocals.wav")
    /// - Returns: URL where audio was saved
    @discardableResult
    public func saveAudio(_ data: Data, name: String) throws -> URL {
        try ensureDirectoriesExist()
        
        let url = audioDirectory.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }
    
    /// Load audio file
    public func loadAudio(name: String) throws -> Data? {
        let url = audioDirectory.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }
    
    /// Get path for audio file (for use with AVFoundation)
    public func audioPath(name: String) -> URL {
        audioDirectory.appendingPathComponent(name)
    }
    
    /// List all audio files
    public func allAudioFiles() throws -> [URL] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: audioDirectory.path) else { return [] }
        
        let contents = try fm.contentsOfDirectory(at: audioDirectory, includingPropertiesForKeys: nil)
        let audioExtensions = ["wav", "m4a", "mp3", "aac", "flac"]
        return contents.filter { audioExtensions.contains($0.pathExtension.lowercased()) }
    }
    
    // MARK: - Embedding Operations
    
    /// Save a face embedding
    /// - Parameters:
    ///   - embedding: 512-dimensional float array
    ///   - personID: Person ID
    /// - Returns: URL where embedding was saved
    @discardableResult
    public func saveEmbedding(_ embedding: [Float], personID: String) throws -> URL {
        try ensureDirectoriesExist()
        
        let data = embedding.withUnsafeBytes { buffer in
            Data(buffer)
        }
        
        let filename = "\(personID).embedding"
        let url = embeddingsDirectory.appendingPathComponent(filename)
        
        try data.write(to: url)
        return url
    }
    
    /// Load a face embedding
    public func loadEmbedding(personID: String) throws -> [Float]? {
        let filename = "\(personID).embedding"
        let url = embeddingsDirectory.appendingPathComponent(filename)
        
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        
        let data = try Data(contentsOf: url)
        return data.withUnsafeBytes { buffer in
            Array(buffer.bindMemory(to: Float.self))
        }
    }
    
    /// Get embedding path for a person
    public func embeddingPath(personID: String) -> URL {
        let filename = "\(personID).embedding"
        return embeddingsDirectory.appendingPathComponent(filename)
    }
    
    /// Save a voice print
    @discardableResult
    public func saveVoicePrint(_ data: Data, speakerID: String) throws -> URL {
        try ensureDirectoriesExist()
        
        let filename = "\(speakerID).voiceprint"
        let url = embeddingsDirectory.appendingPathComponent(filename)
        
        try data.write(to: url)
        return url
    }
    
    /// Load a voice print
    public func loadVoicePrint(speakerID: String) throws -> Data? {
        let filename = "\(speakerID).voiceprint"
        let url = embeddingsDirectory.appendingPathComponent(filename)
        
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }
    
    // MARK: - Thumbnail Operations
    
    /// Save a person thumbnail
    /// - Parameters:
    ///   - data: Image data (JPEG)
    ///   - personID: Person ID
    /// - Returns: URL where thumbnail was saved
    @discardableResult
    public func saveThumbnail(_ data: Data, personID: String) throws -> URL {
        try ensureDirectoriesExist()
        
        let filename = "\(personID).jpg"
        let url = thumbnailsDirectory.appendingPathComponent(filename)
        
        try data.write(to: url)
        return url
    }
    
    /// Load a person thumbnail
    public func loadThumbnail(personID: String) throws -> Data? {
        let filename = "\(personID).jpg"
        let url = thumbnailsDirectory.appendingPathComponent(filename)
        
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }
    
    /// Get thumbnail path for a person
    public func thumbnailPath(personID: String) -> URL {
        let filename = "\(personID).jpg"
        return thumbnailsDirectory.appendingPathComponent(filename)
    }
    
    // MARK: - Cache Operations
    
    /// Save data to cache
    @discardableResult
    public func saveToCache(_ data: Data, key: String) throws -> URL {
        try ensureDirectoriesExist()
        
        let url = cacheDirectory.appendingPathComponent(key)
        try data.write(to: url)
        return url
    }
    
    /// Load data from cache
    public func loadFromCache(key: String) throws -> Data? {
        let url = cacheDirectory.appendingPathComponent(key)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }
    
    /// Check if cache entry exists
    public func cacheExists(key: String) -> Bool {
        let url = cacheDirectory.appendingPathComponent(key)
        return FileManager.default.fileExists(atPath: url.path)
    }
    
    /// Clear entire cache
    public func clearCache() throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: cacheDirectory.path) {
            try fm.removeItem(at: cacheDirectory)
            try fm.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        }
    }
    
    /// Clear cache entries older than specified age
    public func clearOldCache(olderThan age: TimeInterval) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: cacheDirectory.path) else { return }
        
        let cutoff = Date().addingTimeInterval(-age)
        let contents = try fm.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.contentModificationDateKey])
        
        for file in contents {
            let modDate = try file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? Date()
            if modDate < cutoff {
                try fm.removeItem(at: file)
            }
        }
    }
    
    // MARK: - Generic File Operations
    
    /// Check if a file exists
    public func fileExists(at relativePath: String) -> Bool {
        let url = baseDirectory.appendingPathComponent(relativePath)
        return FileManager.default.fileExists(atPath: url.path)
    }
    
    /// Read a file
    public func readFile(at relativePath: String) throws -> Data {
        let url = baseDirectory.appendingPathComponent(relativePath)
        return try Data(contentsOf: url)
    }
    
    /// Write a file
    public func writeFile(at relativePath: String, data: Data) throws {
        let url = baseDirectory.appendingPathComponent(relativePath)
        let dir = url.deletingLastPathComponent()
        
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try data.write(to: url)
    }
    
    /// Delete a file
    public func deleteFile(at relativePath: String) throws {
        let url = baseDirectory.appendingPathComponent(relativePath)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
    
    // MARK: - Private Helpers
    
    private func formatTime(_ time: TimeInterval) -> String {
        String(format: "%010.3f", time).replacingOccurrences(of: ".", with: "_")
    }
    
    private func parseTimeFromFilename(_ filename: String) -> TimeInterval? {
        // Extract time from patterns like "frame_0000000001_234.jpg"
        let components = filename.components(separatedBy: "_")
        guard components.count >= 2 else { return nil }
        
        // Find the time part (should be digits with potential underscore for decimal)
        for (index, component) in components.enumerated() {
            // Check if this looks like a time value
            let cleaned = component.replacingOccurrences(of: ".jpg", with: "")
                .replacingOccurrences(of: ".png", with: "")
            
            if let nextIndex = components.index(index, offsetBy: 1, limitedBy: components.count - 1),
               cleaned.allSatisfy({ $0.isNumber }),
               components[nextIndex].allSatisfy({ $0.isNumber }) {
                let timeString = "\(cleaned).\(components[nextIndex])"
                return TimeInterval(timeString)
            }
        }
        
        return nil
    }
}

// MARK: - File Store Statistics

extension FileStore {
    
    /// Get statistics about stored files
    public func statistics() throws -> FileStoreStatistics {
        var stats = FileStoreStatistics()
        
        let fm = FileManager.default
        
        // Count files in each directory
        if fm.fileExists(atPath: masksDirectory.path) {
            let contents = try fm.contentsOfDirectory(at: masksDirectory, includingPropertiesForKeys: [.fileSizeKey])
            stats.maskCount = contents.count
            stats.maskSize = try contents.reduce(0) { sum, url in
                sum + Int64(try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
            }
        }
        
        if fm.fileExists(atPath: framesDirectory.path) {
            let contents = try fm.contentsOfDirectory(at: framesDirectory, includingPropertiesForKeys: [.fileSizeKey])
            stats.frameCount = contents.count
            stats.frameSize = try contents.reduce(0) { sum, url in
                sum + Int64(try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
            }
        }
        
        if fm.fileExists(atPath: audioDirectory.path) {
            let contents = try fm.contentsOfDirectory(at: audioDirectory, includingPropertiesForKeys: [.fileSizeKey])
            stats.audioFileCount = contents.count
            stats.audioSize = try contents.reduce(0) { sum, url in
                sum + Int64(try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
            }
        }
        
        if fm.fileExists(atPath: embeddingsDirectory.path) {
            let contents = try fm.contentsOfDirectory(at: embeddingsDirectory, includingPropertiesForKeys: [.fileSizeKey])
            stats.embeddingCount = contents.count
            stats.embeddingSize = try contents.reduce(0) { sum, url in
                sum + Int64(try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
            }
        }
        
        if fm.fileExists(atPath: thumbnailsDirectory.path) {
            let contents = try fm.contentsOfDirectory(at: thumbnailsDirectory, includingPropertiesForKeys: [.fileSizeKey])
            stats.thumbnailCount = contents.count
            stats.thumbnailSize = try contents.reduce(0) { sum, url in
                sum + Int64(try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
            }
        }
        
        if fm.fileExists(atPath: cacheDirectory.path) {
            let contents = try fm.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.fileSizeKey])
            stats.cacheSize = try contents.reduce(0) { sum, url in
                sum + Int64(try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
            }
        }
        
        return stats
    }
}

// MARK: - File Store Statistics Type

/// Statistics about file store usage
public struct FileStoreStatistics: Sendable {
    public var maskCount: Int = 0
    public var maskSize: Int64 = 0
    
    public var frameCount: Int = 0
    public var frameSize: Int64 = 0
    
    public var audioFileCount: Int = 0
    public var audioSize: Int64 = 0
    
    public var embeddingCount: Int = 0
    public var embeddingSize: Int64 = 0
    
    public var thumbnailCount: Int = 0
    public var thumbnailSize: Int64 = 0
    
    public var cacheSize: Int64 = 0
    
    /// Total size of all stored files
    public var totalSize: Int64 {
        maskSize + frameSize + audioSize + embeddingSize + thumbnailSize + cacheSize
    }
    
    /// Human-readable total size
    public var formattedTotalSize: String {
        ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }
}
