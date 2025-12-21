import Foundation

/// LiDAR/depth sidecar naming conventions (v1).
///
/// This does not define the on-disk encoding yet; it only standardizes discovery so ingest and tests
/// can be wired deterministically ahead of Asset C landing.
public enum DepthSidecarLocatorV1 {

    /// Candidate sidecar locations for a given video URL.
    ///
    /// Conventions (checked in this order):
    /// - `<base>.depth.v1.mov`  (future: encoded depth video track)
    /// - `<base>.depth.v1.exr`  (future: single-frame debug/thumbnail)
    /// - `<base>.depth.v1.bin` + `<base>.depth.v1.json` (future: packed frames + manifest)
    /// - `<base>.depth.v1/` directory (future: per-frame files)
    public static func candidateSidecarURLs(forVideoURL videoURL: URL) -> [URL] {
        let base = videoURL.deletingPathExtension()
        return [
            base.appendingPathExtension("depth.v1.mov"),
            base.appendingPathExtension("depth.v1.exr"),
            base.appendingPathExtension("depth.v1.json"),
            base.appendingPathExtension("depth.v1.bin"),
            base.appendingPathExtension("depth.v1")
        ]
    }

    public static func firstExistingSidecarURL(forVideoURL videoURL: URL) -> URL? {
        let fm = FileManager.default
        for url in candidateSidecarURLs(forVideoURL: videoURL) {
            if fm.fileExists(atPath: url.path) {
                return url
            }
        }
        return nil
    }
}
