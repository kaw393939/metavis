import Foundation
import OSLog

/// Centralized logging subsystem for MetaVis.
/// Uses Apple's Unified Logging System (OSLog) for high-performance, structured logging.
///
/// Usage:
/// ```swift
/// Log.core.info("System initialized")
/// Log.graph.error("Failed to connect nodes: \(error)")
/// ```
public struct Log {
    /// The subsystem identifier.
    private static let subsystem = "com.metavis.core"
    
    /// Core system events (lifecycle, configuration).
    public static let core = Logger(subsystem: subsystem, category: "Core")
    
    /// Graph manipulation events (nodes, edges, connections).
    public static let graph = Logger(subsystem: subsystem, category: "Graph")
    
    /// Data persistence events (save, load, export).
    public static let persistence = Logger(subsystem: subsystem, category: "Persistence")
    
    /// Resource management events (assets, files).
    public static let resources = Logger(subsystem: subsystem, category: "Resources")
    
    /// Timing and synchronization events.
    public static let timing = Logger(subsystem: subsystem, category: "Timing")
    
    /// Virtual Device events (cameras, lights, generators).
    public static let device = Logger(subsystem: subsystem, category: "Device")
}
