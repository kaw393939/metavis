import Foundation
import MetaVisCore
import MetaVisTimeline
import MetaVisSession
import MetaVisIngest
import MetaVisSimulation
import MetaVisExport

@main
struct MetaVisLab {
    static func main() async {
        print("🧪 Starting MetaVis Lab \"Gemini Loop\" Verification")
        
        do {
            // 1. Setup Session
            let license = ProjectLicense(ownerId: "lab", maxExportResolution: 4320, requiresWatermark: true, allowOpenEXR: false)
            let session = ProjectSession(initialState: ProjectState(config: ProjectConfig(name: "Lab Validation Project", license: license)))
            print("✅ Session Initialized")
            
            // 2. Setup Device
            let ligm = LIGMDevice()
            print("✅ LIGM Device Connected")
            
            // 3. Generate Content
            print("⏳ Generating Asset...")
            let result = try await ligm.perform(action: "generate", with: ["prompt": .string("Test Pattern ACEScg")])
            
            guard case .string(let assetId) = result["assetId"],
                  case .string(let sourceUrl) = result["sourceUrl"] else {
                print("❌ Generation Failed: Missing outputs")
                exit(1)
            }
            print("✅ Generated Asset: \(assetId)")
            
            // 4. Edit Timeline
            // Create a Track
            let trackId = UUID()
            let track = Track(id: trackId, name: "Video Layer 1")
            await session.dispatch(.addTrack(track))
            print("✅ Track Added: \(track.name)")
            
            // Create a Clip
            let assetRef = AssetReference(id: UUID(), sourceFn: sourceUrl)
            let clip = Clip(
                name: "Test Pattern",
                asset: assetRef,
                startTime: .zero,
                duration: Time(seconds: 10.0)
            )
            
            // Add Clip to Track
            await session.dispatch(.addClip(clip, toTrackId: trackId))
            print("✅ Clip Added: \(clip.name) to \(track.name)")
            
            // 5. Verification
            let state = await session.state
            let clipCount = state.timeline.tracks.first?.clips.count ?? 0
            
            if clipCount == 1 {
                print("🎉 SUCCESS: Lab Project Created Successfully!")
                print("   - Project: \(state.config.name)")
                print("   - Timeline: \(state.timeline.tracks.count) Track, \(clipCount) Clip")
                print("   - Asset Source: \(sourceUrl)")

                // 6. Export (governance enforced via ProjectSession)
                let engine = try MetalSimulationEngine()
                let exporter = VideoExporter(engine: engine)
                let outputURL = URL(fileURLWithPath: "\(FileManager.default.currentDirectoryPath)/test_outputs/lab_watermarked_1080p.mov")
                let quality = QualityProfile(name: "Lab1080", fidelity: .high, resolutionHeight: 1080, colorDepth: 10)
                print("⏳ Exporting to: \(outputURL.path)")
                try await session.exportMovie(using: exporter, to: outputURL, quality: quality, frameRate: 24, codec: .hevc, audioPolicy: .auto)
                print("✅ Export Complete")
            } else {
                print("❌ FAILURE: Clip not found in timeline.")
                exit(1)
            }
            
        } catch {
            print("❌ Error: \(error)")
            exit(1)
        }
    }
}
