// PDFToVideoGenerator.swift
// MetaVisRender
//
// Created for Sprint 14: Validation
// Generates animated videos from PDF documents with Gemini-assisted narration

import Foundation
import Metal
import CoreGraphics

// MARK: - PDF to Video Generator

/// Generates animated videos from PDF documents with various transition effects
public actor PDFToVideoGenerator {
    
    // MARK: - Configuration
    
    public struct Config: Sendable {
        /// Seconds to display each page
        public let secondsPerPage: Double
        /// Frames per second for output video
        public let fps: Double
        /// Output resolution
        public let resolution: SIMD2<Int>
        /// Animation style
        public let animationStyle: AnimationStyle
        /// Transition between pages
        public let pageTransition: PageTransition
        /// Background color
        public let backgroundColor: CGColor
        
        public init(
            secondsPerPage: Double = 5.0,
            fps: Double = 30.0,
            resolution: SIMD2<Int> = SIMD2(1920, 1080),
            animationStyle: AnimationStyle = .slideIn,
            pageTransition: PageTransition = .crossfade(duration: 0.5),
            backgroundColor: CGColor = CGColor(gray: 0.0, alpha: 1.0)
        ) {
            self.secondsPerPage = secondsPerPage
            self.fps = fps
            self.resolution = resolution
            self.animationStyle = animationStyle
            self.pageTransition = pageTransition
            self.backgroundColor = backgroundColor
        }
        
        public static let presentation = Config(
            secondsPerPage: 5.0,
            animationStyle: .slideIn,
            pageTransition: .crossfade(duration: 0.5)
        )
        
        public static let crawl = Config(
            secondsPerPage: 8.0,
            animationStyle: .crawlUp,
            pageTransition: .none
        )
    }
    
    public enum AnimationStyle: Sendable {
        case none
        case slideIn
        case slideInLeft
        case slideInRight
        case crawlUp  // Star Wars style
        case zoomIn
        case fadeIn
    }
    
    public enum PageTransition: Sendable {
        case none
        case crossfade(duration: Double)
        case slide(duration: Double)
        case wipe(duration: Double)
    }
    
    // MARK: - Properties
    
    private let config: Config
    private let device: MTLDevice
    private let pageRenderer: PageRenderer
    
    // MARK: - Initialization
    
    public init(config: Config = .presentation, device: MTLDevice? = nil) throws {
        self.config = config
        self.device = device ?? MTLCreateSystemDefaultDevice()!
        
        let rendererConfig = PageRenderer.Config(
            dpi: 150,
            backgroundColor: config.backgroundColor
        )
        self.pageRenderer = PageRenderer(config: rendererConfig, device: self.device)
    }
    
    // MARK: - Generation
    
    /// Generate video from PDF with optional Gemini narration
    public func generate(
        pdfURL: URL,
        outputURL: URL,
        withNarration: Bool = false,
        geminiSummary: String? = nil
    ) async throws -> GenerationResult {
        // 1. Analyze PDF
        let analyzer = DocumentAnalysisEngine()
        let analysis = try await analyzer.analyze(pdfURL)
        
        print("PDF Analysis: \(analysis.pageCount) pages, \(analysis.wordCount) words")
        
        // 2. Optional: Generate Gemini summary and narration
        var narrationURL: URL?
        if withNarration {
            narrationURL = try await generateNarration(
                pdfURL: pdfURL,
                analysis: analysis,
                providedSummary: geminiSummary
            )
        }
        
        // 3. Export video directly (no timeline needed for simple image sequence)
        try await exportPDFToVideo(
            pdfURL: pdfURL,
            outputURL: outputURL,
            pageCount: analysis.pageCount,
            audioURL: narrationURL
        )
        
        return GenerationResult(
            outputURL: outputURL,
            pageCount: analysis.pageCount,
            duration: Double(analysis.pageCount) * config.secondsPerPage,
            fps: config.fps,
            narrationURL: narrationURL
        )
    }
    
    // MARK: - Narration Generation
    
    private func generateNarration(
        pdfURL: URL,
        analysis: DocumentAnalysis,
        providedSummary: String?
    ) async throws -> URL {
        // Get or generate summary
        let summary: String
        if let provided = providedSummary {
            summary = provided
        } else {
            // Use Gemini to analyze PDF
            let gemini = try GeminiClient()
            print("Uploading PDF to Gemini...")
            let uploadResponse = try await gemini.uploadFile(pdfURL)
            print("Analyzing with Gemini...")
            summary = try await gemini.analyzePDF(uploadResponse.file.uri)
        }
        
        // Generate narration with ElevenLabs
        let elevenlabs = try ElevenLabsClient()
        let narratorVoice = "21m00Tcm4TlvDq8ikWAM"  // Rachel - professional narrator
        
        print("Generating narration...")
        let audioURL = try await elevenlabs.generateSpeech(
            text: summary,
            voiceId: narratorVoice,
            modelId: "eleven_turbo_v2_5"
        )
        
        return audioURL
    }
    
    // MARK: - Page Rendering
    
    private func renderPages(pdfURL: URL, pageCount: Int) async throws -> [MTLTexture] {
        var textures: [MTLTexture] = []
        
        print("Rendering \(pageCount) pages...")
        for pageIndex in 0..<pageCount {
            // PageRenderer uses 1-based page numbering
            let texture = try await pageRenderer.renderToTexture(
                page: pageIndex + 1,
                from: pdfURL,
                resolution: CGSize(
                    width: CGFloat(config.resolution.x),
                    height: CGFloat(config.resolution.y)
                )
            )
            textures.append(texture)
            
            if (pageIndex + 1) % 5 == 0 {
                print("  Rendered \(pageIndex + 1)/\(pageCount) pages")
            }
        }
        
        return textures
    }
    
    // MARK: - Video Export (Using Timeline System)
    
    private func exportPDFToVideo(
        pdfURL: URL,
        outputURL: URL,
        pageCount: Int,
        audioURL: URL?
    ) async throws {
        print("Exporting video via timeline system...")
        
        // 1. Create a timeline with PDF pages as sources
        var timeline = TimelineModel(
            fps: config.fps,
            resolution: config.resolution
        )
        
        // 2. Register each PDF page as a source in the timeline
        for pageIndex in 0..<pageCount {
            let sourceID = "page_\(pageIndex + 1)"
            timeline.registerSource(
                id: sourceID,
                path: pdfURL.path,  // Placeholder path for timeline compatibility
                duration: config.secondsPerPage
            )
        }
        
        // 3. Create a single video track
        _ = timeline.addVideoTrack(name: "PDF Pages")
        
        // 4. Add clips for each page
        var currentTime: Double = 0
        for pageIndex in 0..<pageCount {
            let sourceID = "page_\(pageIndex + 1)"
            let clip = ClipDefinition(
                source: sourceID,
                sourceIn: 0,
                sourceOut: config.secondsPerPage,
                timelineIn: currentTime,
                speed: 1.0
            )
            
            timeline.videoTracks[0].clips.append(clip)
            currentTime += config.secondsPerPage
        }
        
        print("  Timeline created: \(pageCount) clips, \(timeline.duration)s total")
        
        // 5. Create unified decoder with custom PDF page sources
        let decoder = UnifiedSourceDecoder(device: device, timeline: timeline)
        
        // Register each page as a custom frame source
        for pageIndex in 0..<pageCount {
            let sourceID = "page_\(pageIndex + 1)"
            let pdfSource = PDFPageSource(
                sourceID: sourceID,
                pdfURL: pdfURL,
                pageNumber: pageIndex + 1,  // PageRenderer uses 1-based indexing
                resolution: config.resolution,
                pageRenderer: pageRenderer
            )
            await decoder.registerFrameSource(id: sourceID, source: pdfSource)
        }
        
        print("  Registered \(pageCount) PDF page sources")
        
        // 6. Export using TimelineExporter (the proper way!)
        let exporter = try TimelineExporter(
            timeline: timeline,
            device: device,
            outputURL: outputURL,
        )
        
        try await exporter.export { progress in
            if progress.currentFrame % 30 == 0 || progress.currentFrame == progress.totalFrames - 1 {
                print("  Progress: \(progress.percentage)% (\(progress.currentFrame)/\(progress.totalFrames) frames)")
            }
        }
        
        print("  ✓ Video export complete via timeline system")
        
        // TODO: Mix in audio if provided
        if let audioURL = audioURL {
            print("  Note: Audio mixing not yet implemented")
            print("  Audio file: \(audioURL.path)")
        }
    }
}

// MARK: - Result Types

public struct GenerationResult {
    public let outputURL: URL
    public let pageCount: Int
    public let duration: Double
    public let fps: Double
    public let narrationURL: URL?
}

// MARK: - Errors

public enum PDFToVideoError: LocalizedError {
    case notImplemented(String)
    case invalidPDF
    case renderingFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .notImplemented(let message):
            return "Not implemented: \(message)"
        case .invalidPDF:
            return "Invalid or corrupted PDF"
        case .renderingFailed(let message):
            return "Rendering failed: \(message)"
        }
    }
}
