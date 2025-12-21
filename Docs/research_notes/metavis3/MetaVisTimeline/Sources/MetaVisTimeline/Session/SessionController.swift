import Foundation
import Combine
import MetaVisCore

/// The Controller for the MetaVis Session.
/// This replaces the legacy ProjectDocument.
/// It manages the active session, handles undo/redo (future), and persistence.
@available(macOS 14.0, *)
@MainActor
public class SessionController: ObservableObject {
    
    // MARK: - State
    
    /// The single source of truth.
    @Published public private(set) var session: MetaVisSession
    
    // MARK: - Event Bus
    
    public enum Event {
        case didLoad
        case didUpdateSession
        case didSave
    }
    
    public let events = PassthroughSubject<Event, Never>()
    
    // MARK: - Initialization
    
    public init(session: MetaVisSession = MetaVisSession()) {
        self.session = session
    }
    
    // MARK: - Mutation
    
    /// The ONLY way to change the session state.
    public func update(_ mutation: (inout MetaVisSession) -> Void) {
        mutation(&session)
        events.send(.didUpdateSession)
    }
    
    // MARK: - Persistence
    
    public func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(session)
        try data.write(to: url)
        events.send(.didSave)
    }
    
    public static func load(from url: URL) throws -> SessionController {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        let session = try decoder.decode(MetaVisSession.self, from: data)
        return SessionController(session: session)
    }
}
