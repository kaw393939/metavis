import Foundation
import MetaVisCore

public struct BiteMap: Sendable, Codable, Equatable {
    public static let schemaVersion = 1

    public struct Bite: Sendable, Codable, Equatable {
        public let start: Time
        public let end: Time
        public let personId: String
        public let reason: String

        public init(start: Time, end: Time, personId: String, reason: String) {
            self.start = start
            self.end = end
            self.personId = personId
            self.reason = reason
        }
    }

    public let schemaVersion: Int
    public let bites: [Bite]

    public init(schemaVersion: Int = BiteMap.schemaVersion, bites: [Bite]) {
        self.schemaVersion = schemaVersion
        self.bites = bites
    }
}
