@_exported import MetaVisCore
@_exported import MetaVisServices
@_exported import MetaVisScheduler
@_exported import MetaVisImageGen
@_exported import MetaVisTimeline

// Export Reporting types
// Note: Since Reporting is part of the MetaVisKit target itself, it's automatically available
// to consumers of MetaVisKit, but we need to make sure the files are included in the target.

import Foundation

// Re-export Reporting types for convenience if needed, though they are public in the module.
// The issue might be that MetaVisCLI imports MetaVisKit but the compiler isn't seeing the new files yet?
// Or maybe I need to explicitly import them in the CLI file if they were in a different module, but they are in Kit.


/// MetaVisKit is the unified framework for the MetaVis Render Engine.
/// It aggregates Core, Services, Scheduler, and other modules into a single API.
public struct MetaVis {
    
    /// The shared configuration for the runtime.
    public static var configuration = Configuration()
    
    public struct Configuration {
        public var logLevel: LogLevel = .info
    }
    
    public enum LogLevel {
        case debug, info, warning, error
    }
    
    // MARK: - Factory Methods
    
    /// Creates a new Scheduler with default workers registered.
    public static func createScheduler(queuePath: String? = nil) async throws -> Scheduler {
        let scheduler = try Scheduler(queuePath: queuePath)
        let orchestrator = ServiceOrchestrator()
        
        // Register Providers
        try await orchestrator.register(provider: GoogleProvider())
        try await orchestrator.register(provider: ElevenLabsProvider())
        try await orchestrator.register(provider: LIGMProvider())
        
        // Register default workers
        await scheduler.register(worker: ServiceWorker(orchestrator: orchestrator))
        await scheduler.register(worker: IngestWorker())
        await scheduler.register(worker: RenderWorker())
        
        return scheduler
    }
    
    /// Creates a configured ServiceOrchestrator for direct service interaction.
    public static func createOrchestrator() async throws -> ServiceOrchestrator {
        let orchestrator = ServiceOrchestrator()
        
        // Register Providers
        try await orchestrator.register(provider: GoogleProvider())
        try await orchestrator.register(provider: ElevenLabsProvider())
        try await orchestrator.register(provider: LIGMProvider())
        
        return orchestrator
    }
    
    /// Creates a new Lab Toolkit instance.
    public static func createLab() -> MetaVisLab {
        return MetaVisLab()
    }
}

/// A facade for the Lab tools.
public struct MetaVisLab {
    public let colorPipeline = ColorPipeline()
    public let tools = ColorLabTools()
    
    // LIGM helper would go here
}
