import Foundation
import MetaVisCore

public enum DeliverableSidecarKind: String, Codable, Sendable, Equatable {
    case captionsVTT
    case captionsSRT
    case transcriptWordsJSON
    case thumbnailJPEG
    case contactSheetJPEG
}

public struct DeliverableSidecar: Codable, Sendable, Equatable {
    public var kind: DeliverableSidecarKind
    public var fileName: String

    public init(kind: DeliverableSidecarKind, fileName: String) {
        self.kind = kind
        self.fileName = fileName
    }
}

public enum DeliverableSidecarRequest: Sendable, Equatable {
    case captionsVTT(fileName: String = "captions.vtt", required: Bool = true)
    case captionsSRT(fileName: String = "captions.srt", required: Bool = true)
    /// Word-level transcript contract (JSON). Time mapping is in `MetaVisCore.Time` ticks (1/60000s).
    ///
    /// If `cues` is empty, the writer may fall back to best-effort caption sidecar discovery.
    case transcriptWordsJSON(fileName: String = "transcript_words.json", cues: [CaptionCue] = [], required: Bool = true)
    case thumbnailJPEG(fileName: String = "thumbnail.jpg", required: Bool = true)
    case contactSheetJPEG(fileName: String = "contact_sheet.jpg", columns: Int = 2, rows: Int = 2, required: Bool = true)

    public var isRequired: Bool {
        switch self {
        case .captionsVTT(_, let required):
            return required
        case .captionsSRT(_, let required):
            return required
        case .transcriptWordsJSON(_, _, let required):
            return required
        case .thumbnailJPEG(_, let required):
            return required
        case .contactSheetJPEG(_, _, _, let required):
            return required
        }
    }

    public var kind: DeliverableSidecarKind {
        switch self {
        case .captionsVTT:
            return .captionsVTT
        case .captionsSRT:
            return .captionsSRT
        case .transcriptWordsJSON:
            return .transcriptWordsJSON
        case .thumbnailJPEG:
            return .thumbnailJPEG
        case .contactSheetJPEG:
            return .contactSheetJPEG
        }
    }

    public var fileName: String {
        switch self {
        case .captionsVTT(let fileName, _):
            return fileName
        case .captionsSRT(let fileName, _):
            return fileName
        case .transcriptWordsJSON(let fileName, _, _):
            return fileName
        case .thumbnailJPEG(let fileName, _):
            return fileName
        case .contactSheetJPEG(let fileName, _, _, _):
            return fileName
        }
    }
}
