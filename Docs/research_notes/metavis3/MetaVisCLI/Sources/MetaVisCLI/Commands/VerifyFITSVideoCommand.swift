import Foundation
import ArgumentParser
import MetaVisTimeline
import MetaVisCore
import MetaVisSimulation
import MetaVisScheduler
import MetaVisIngest // Import the new module

struct VerifyFITSVideoCommand: AsyncParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "verify-fits-video",
        abstract: "Generates a video using JWST FITS data."
    )
    
    @Option(name: .shortAndLong, help: "Output path (optional). Defaults to ./renders/fits_demo.mov")
    var output: String?
    
    func run() async throws {
        print("🔭 Starting FITS Video Generation (Refactored Tool-Device Pipeline)...")
        
        // 1. Setup Project Context
        var project = Project(name: "JWST Verification", mode: .astrophysics)
        
        // 2. Setup Devices
        // We create the specific devices needed for this task
        var fitsDevice = FITSDevice()
        fitsDevice.parameters["searchPath"] = .string("/Users/kwilliams/Projects/metavis_render_two/assets")
        // let renderDevice = RenderDevice() // Future
        
        let devices: [any VirtualDevice] = [fitsDevice]
        
        // 3. Run Ingest Tool
        let ingestTool = IngestTool()
        try await ingestTool.run(project: &project, devices: devices)
        
        // 4. Create Timeline
        print("   🎞️ Creating Timeline...")
        var timeline = Timeline(name: "FITS Demo Timeline")
        var track = Track(name: "Video Track", type: .video)
        
        var currentTime = RationalTime.zero
        let clipDuration = RationalTime(value: 5, timescale: 1) // 5 seconds per asset
        
        for asset in project.assets {
            let range = TimeRange(start: currentTime, duration: clipDuration)
            let clip = Clip(
                name: asset.name,
                assetId: asset.id,
                range: range,
                sourceStartTime: .zero
            )
            try track.add(clip)
            currentTime = range.end
        }
        
        timeline.addTrack(track)
        
        // 5. Render
        let outputURL = URL(fileURLWithPath: output ?? "./renders/fits_demo.mov")
        let outputDirectory = outputURL.deletingLastPathComponent()
        
        // Ensure output directory exists
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        
        let assetInfos = project.assets.map { AssetInfo(id: $0.id, name: $0.name, url: $0.url!, type: $0.type) }
        
        let payload = RenderJobPayload(
            timeline: timeline,
            outputPath: outputURL.path,
            width: 1920,
            height: 1080,
            assets: assetInfos
        )
        
        let job = Job(
            id: UUID(),
            type: .render,
            status: .pending,
            priority: 10,
            payload: try JSONEncoder().encode(payload)
        )
        
        let worker = RenderWorker()
        print("🚀 Starting Render...")
        _ = try await worker.execute(job: job) { progress in
            print("   Render Progress: \(Int(progress.progress * 100))% - \(progress.message)")
        }
        print("✅ Render Complete: \(outputURL.path)")
        
        // 6. Feedback
        print("🤖 Requesting Feedback...")
        
        // We can invoke the FeedbackCommand logic directly or via a new instance
        // Since FeedbackCommand is an AsyncParsableCommand, we can instantiate it and run it?
        // Or just reuse the logic. Reusing logic is safer if we can access it.
        // But FeedbackCommand is in the same module.
        
        var feedbackCmd = FeedbackCommand()
        feedbackCmd.input = outputURL.path
        feedbackCmd.prompt = "Analyze this video of JWST data. Does it look like a valid visualization of astronomical data? Are there any artifacts?"
        try await feedbackCmd.run()
    }
}

