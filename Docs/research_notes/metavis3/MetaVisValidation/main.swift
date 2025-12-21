import Foundation
import MetaVisSimulation
import Metal

@main
struct ValidationMain {
    static func main() async {
        print("🚀 Starting Validation...")
        
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("❌ Metal device not available.")
            return
        }
        
        let assetsDir = URL(fileURLWithPath: "/Users/kwilliams/Projects/metavis_render_two/assets")
        let files = [
            "hlsp_jwst-ero_jwst_miri_carina_f770w_v1_i2d.fits",
            "hlsp_jwst-ero_jwst_miri_carina_f1130w_v1_i2d.fits",
            "hlsp_jwst-ero_jwst_miri_carina_f1280w_v1_i2d.fits",
            "hlsp_jwst-ero_jwst_miri_carina_f1800w_v1_i2d.fits"
        ]
        
        let importer = FITSImporter(device: device)
        
        for file in files {
            let url = assetsDir.appendingPathComponent(file)
            print("\n📂 Loading \(file)...")
            do {
                // This should trigger the print stats logic I added to FITSImporter
                let texture = try await importer.loadTexture(from: url)
                print("✅ Loaded texture: \(texture.width)x\(texture.height)")
            } catch {
                print("❌ Failed to load \(file): \(error)")
            }
        }
        
        print("\n🏁 Validation Complete.")
    }
}
