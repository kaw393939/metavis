import Foundation

/// Knowledge graph data structure
public struct GraphData: Codable, Sendable {
    public let nodes: [Node]
    public let edges: [Edge]
    public let layout: LayoutType?

    public init(nodes: [Node], edges: [Edge], layout: LayoutType? = nil) {
        self.nodes = nodes
        self.edges = edges
        self.layout = layout
    }

    public struct Node: Codable, Sendable {
        public let id: String
        public let label: String
        public let type: String?
        public let size: Float?
        public let color: [Float]?
        public let position: [Float]? // [x, y, z] optional fixed position

        public init(
            id: String,
            label: String,
            type: String? = nil,
            size: Float? = nil,
            color: [Float]? = nil,
            position: [Float]? = nil
        ) {
            self.id = id
            self.label = label
            self.type = type
            self.size = size
            self.color = color
            self.position = position
        }
    }

    public struct Edge: Codable, Sendable {
        public let source: String
        public let target: String
        public let weight: Float?
        public let label: String?
        public let color: [Float]?

        public init(
            source: String,
            target: String,
            weight: Float? = nil,
            label: String? = nil,
            color: [Float]? = nil
        ) {
            self.source = source
            self.target = target
            self.weight = weight
            self.label = label
            self.color = color
        }
    }

    public enum LayoutType: String, Codable, Sendable {
        case forceDirected = "force_directed"
        case hierarchical
        case circular
        case grid
    }
}

/// Timeline data structure
public struct TimelineData: Codable, Sendable {
    public let events: [Event]
    public let style: Style?

    public init(events: [Event], style: Style? = nil) {
        self.events = events
        self.style = style
    }

    public struct Event: Codable, Sendable {
        public let date: String // ISO 8601 date string
        public let title: String
        public let description: String?
        public let location: String?
        public let importance: Float? // 0.0-1.0
        public let color: [Float]?

        public init(
            date: String,
            title: String,
            description: String? = nil,
            location: String? = nil,
            importance: Float? = nil,
            color: [Float]? = nil
        ) {
            self.date = date
            self.title = title
            self.description = description
            self.location = location
            self.importance = importance
            self.color = color
        }
    }

    public enum Style: String, Codable, Sendable {
        case horizontal
        case vertical
        case spiral
    }
}

/// Geographic data structure
public struct GeographicData: Codable, Sendable {
    public let locations: [Location]
    public let flows: [Flow]?
    public let projection: Projection?

    public init(locations: [Location], flows: [Flow]? = nil, projection: Projection? = nil) {
        self.locations = locations
        self.flows = flows
        self.projection = projection
    }

    public struct Location: Codable, Sendable {
        public let id: String
        public let latitude: Double
        public let longitude: Double
        public let label: String
        public let value: Float? // For heat maps
        public let color: [Float]?

        public init(
            id: String,
            latitude: Double,
            longitude: Double,
            label: String,
            value: Float? = nil,
            color: [Float]? = nil
        ) {
            self.id = id
            self.latitude = latitude
            self.longitude = longitude
            self.label = label
            self.value = value
            self.color = color
        }
    }

    public struct Flow: Codable, Sendable {
        public let from: String
        public let to: String
        public let magnitude: Float
        public let color: [Float]?

        public init(from: String, to: String, magnitude: Float, color: [Float]? = nil) {
            self.from = from
            self.to = to
            self.magnitude = magnitude
            self.color = color
        }
    }

    public enum Projection: String, Codable, Sendable {
        case mercator
        case equirectangular
        case globe3D = "globe_3d"
    }
}

/// Chart data structure
public struct ChartData: Codable, Sendable {
    public let type: ChartType
    public let series: [Series]
    public let labels: [String]?
    public let title: String?

    public init(type: ChartType, series: [Series], labels: [String]? = nil, title: String? = nil) {
        self.type = type
        self.series = series
        self.labels = labels
        self.title = title
    }

    public enum ChartType: String, Codable, Sendable {
        case bar
        case line
        case area
        case pie
        case racingBar = "racing_bar"
    }

    public struct Series: Codable, Sendable {
        public let name: String
        public let values: [Float]
        public let color: [Float]?

        public init(name: String, values: [Float], color: [Float]? = nil) {
            self.name = name
            self.values = values
            self.color = color
        }
    }
}

/// Network flow data structure
public struct NetworkFlowData: Codable, Sendable {
    public let nodes: [String]
    public let flows: [Flow]
    public let layout: LayoutType?

    public init(nodes: [String], flows: [Flow], layout: LayoutType? = nil) {
        self.nodes = nodes
        self.flows = flows
        self.layout = layout
    }

    public struct Flow: Codable, Sendable {
        public let source: String
        public let target: String
        public let value: Float
        public let label: String?

        public init(source: String, target: String, value: Float, label: String? = nil) {
            self.source = source
            self.target = target
            self.value = value
            self.label = label
        }
    }

    public enum LayoutType: String, Codable, Sendable {
        case sankey
        case chord
        case matrix
    }
}
