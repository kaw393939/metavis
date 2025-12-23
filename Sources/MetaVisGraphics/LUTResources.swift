import Foundation

public enum LUTResources {
    private static func loadCube(named name: String) -> Data? {
        let candidates: [String?] = [
            "LUTs",
            "Resources/LUTs",
            nil
        ]

        for subdir in candidates {
            if let url = Bundle.module.url(forResource: name, withExtension: "cube", subdirectory: subdir) {
                return try? Data(contentsOf: url)
            }
        }

        // As a last resort, try walking from the resource root.
        if let base = Bundle.module.resourceURL {
            let paths = [
                base.appendingPathComponent("LUTs/\(name).cube"),
                base.appendingPathComponent("Resources/LUTs/\(name).cube")
            ]
            for url in paths {
                if let data = try? Data(contentsOf: url) {
                    return data
                }
            }
        }

        return nil
    }

    /// ACES 1.3 reference-ish SDR display transform baked from the official
    /// OpenColorIO-Config-ACES ACES 1.3 cg-config.
    ///
    /// Baked command (documented in research notes):
    /// `ociobakelut --inputspace ACEScg --displayview "sRGB - Display" "ACES 1.0 - SDR Video" --shapersize 4096 --cubesize 33 --format iridas_cube`
    public static func aces13SDRSRGBDisplayRRTODT33() -> Data? {
        loadCube(named: "aces13_sdr_srgb_display_rrt_odt_33")
    }

    /// ACES 1.3 reference-ish HDR PQ 1000-nit display transform baked from the official
    /// OpenColorIO-Config-ACES ACES 1.3 cg-config.
    ///
    /// Baked command (documented in research notes):
    /// `ociobakelut --inputspace ACEScg --displayview "Rec.2100-PQ - Display" "ACES 1.1 - HDR Video (1000 nits & Rec.2020 lim)" --shapersize 4096 --cubesize 33 --format iridas_cube`
    public static func aces13HDRRec2100PQ1000DisplayRRTODT33() -> Data? {
        loadCube(named: "aces13_hdr_rec2100pq1000_display_rrt_odt_33")
    }
}
