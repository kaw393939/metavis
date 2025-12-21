// PerformanceMonitor.swift
// MetaVisRender
//
// Created for Sprint 03: Real-time performance monitoring
// Tracks thermal state, memory pressure, GPU/ANE utilization

import Foundation
#if canImport(Metal)
import Metal
#endif

// MARK: - Thermal State

/// Current device thermal state
public enum ThermalState: String, Codable, Sendable {
    case nominal = "nominal"
    case fair = "fair"
    case serious = "serious"
    case critical = "critical"
    
    /// Create from ProcessInfo thermal state
    public init(from processInfo: ProcessInfo.ThermalState) {
        switch processInfo {
        case .nominal:
            self = .nominal
        case .fair:
            self = .fair
        case .serious:
            self = .serious
        case .critical:
            self = .critical
        @unknown default:
            self = .nominal
        }
    }
    
    /// Whether the device should throttle workloads
    public var shouldThrottle: Bool {
        switch self {
        case .nominal, .fair:
            return false
        case .serious, .critical:
            return true
        }
    }
    
    /// Recommended concurrent operation limit multiplier
    public var concurrencyMultiplier: Double {
        switch self {
        case .nominal: return 1.0
        case .fair: return 0.8
        case .serious: return 0.5
        case .critical: return 0.25
        }
    }
}

// MARK: - Memory Pressure

/// Current system memory pressure level
public enum MemoryPressure: String, Codable, Sendable {
    case normal = "normal"
    case warning = "warning"
    case critical = "critical"
    
    /// Whether memory-intensive operations should pause
    public var shouldPause: Bool {
        self == .critical
    }
    
    /// Recommended memory usage multiplier
    public var memoryMultiplier: Double {
        switch self {
        case .normal: return 1.0
        case .warning: return 0.7
        case .critical: return 0.4
        }
    }
}

// MARK: - Performance Snapshot

/// Point-in-time snapshot of system performance
public struct PerformanceSnapshot: Codable, Sendable {
    /// Timestamp of this snapshot
    public let timestamp: Date
    
    /// Current thermal state
    public let thermalState: ThermalState
    
    /// Current memory pressure
    public let memoryPressure: MemoryPressure
    
    /// Memory currently used by this process (bytes)
    public let processMemoryUsage: UInt64
    
    /// System-wide memory available (bytes)
    public let availableMemory: UInt64
    
    /// CPU usage percentage (0-100)
    public let cpuUsage: Double
    
    /// GPU usage percentage (0-100, if available)
    public let gpuUsage: Double?
    
    /// ANE usage percentage (0-100, if available)
    public let aneUsage: Double?
    
    /// Current power state
    public let isLowPowerMode: Bool
    
    /// Battery level (0-100, nil if not applicable)
    public let batteryLevel: Int?
    
    /// Is device plugged in
    public let isPluggedIn: Bool?
    
    public init(
        timestamp: Date = Date(),
        thermalState: ThermalState,
        memoryPressure: MemoryPressure,
        processMemoryUsage: UInt64,
        availableMemory: UInt64,
        cpuUsage: Double,
        gpuUsage: Double?,
        aneUsage: Double?,
        isLowPowerMode: Bool,
        batteryLevel: Int?,
        isPluggedIn: Bool?
    ) {
        self.timestamp = timestamp
        self.thermalState = thermalState
        self.memoryPressure = memoryPressure
        self.processMemoryUsage = processMemoryUsage
        self.availableMemory = availableMemory
        self.cpuUsage = cpuUsage
        self.gpuUsage = gpuUsage
        self.aneUsage = aneUsage
        self.isLowPowerMode = isLowPowerMode
        self.batteryLevel = batteryLevel
        self.isPluggedIn = isPluggedIn
    }
}

// MARK: - Performance Statistics

/// Aggregated performance statistics over a time window
public struct PerformanceStatistics: Codable, Sendable {
    /// Start of measurement window
    public let windowStart: Date
    
    /// End of measurement window
    public let windowEnd: Date
    
    /// Number of samples collected
    public let sampleCount: Int
    
    /// Average CPU usage
    public let avgCpuUsage: Double
    
    /// Peak CPU usage
    public let peakCpuUsage: Double
    
    /// Average memory usage (bytes)
    public let avgMemoryUsage: UInt64
    
    /// Peak memory usage (bytes)
    public let peakMemoryUsage: UInt64
    
    /// Average GPU usage (if available)
    public let avgGpuUsage: Double?
    
    /// Peak GPU usage (if available)
    public let peakGpuUsage: Double?
    
    /// Average ANE usage (if available)
    public let avgAneUsage: Double?
    
    /// Peak ANE usage (if available)
    public let peakAneUsage: Double?
    
    /// Thermal throttle occurrences
    public let thermalThrottleCount: Int
    
    /// Memory warning occurrences
    public let memoryWarningCount: Int
    
    public init(
        windowStart: Date,
        windowEnd: Date,
        sampleCount: Int,
        avgCpuUsage: Double,
        peakCpuUsage: Double,
        avgMemoryUsage: UInt64,
        peakMemoryUsage: UInt64,
        avgGpuUsage: Double?,
        peakGpuUsage: Double?,
        avgAneUsage: Double?,
        peakAneUsage: Double?,
        thermalThrottleCount: Int,
        memoryWarningCount: Int
    ) {
        self.windowStart = windowStart
        self.windowEnd = windowEnd
        self.sampleCount = sampleCount
        self.avgCpuUsage = avgCpuUsage
        self.peakCpuUsage = peakCpuUsage
        self.avgMemoryUsage = avgMemoryUsage
        self.peakMemoryUsage = peakMemoryUsage
        self.avgGpuUsage = avgGpuUsage
        self.peakGpuUsage = peakGpuUsage
        self.avgAneUsage = avgAneUsage
        self.peakAneUsage = peakAneUsage
        self.thermalThrottleCount = thermalThrottleCount
        self.memoryWarningCount = memoryWarningCount
    }
}

// MARK: - Performance Monitor

/// Actor that continuously monitors system performance
public actor PerformanceMonitor {
    
    // MARK: - Properties
    
    /// Whether monitoring is currently active
    private(set) public var isMonitoring: Bool = false
    
    /// Collected snapshots
    private var snapshots: [PerformanceSnapshot] = []
    
    /// Maximum snapshots to retain
    private let maxSnapshots: Int
    
    /// Monitoring interval in seconds
    private let interval: TimeInterval
    
    /// Active monitoring task
    private var monitoringTask: Task<Void, Never>?
    
    /// Thermal state change handlers
    private var thermalHandlers: [(ThermalState) -> Void] = []
    
    /// Memory pressure change handlers
    private var memoryHandlers: [(MemoryPressure) -> Void] = []
    
    /// Last known states for change detection
    private var lastThermalState: ThermalState = .nominal
    private var lastMemoryPressure: MemoryPressure = .normal
    
    // MARK: - Initialization
    
    /// Create a performance monitor
    /// - Parameters:
    ///   - interval: Sampling interval in seconds (default 1.0)
    ///   - maxSnapshots: Maximum snapshots to retain (default 3600 = 1 hour at 1s)
    public init(interval: TimeInterval = 1.0, maxSnapshots: Int = 3600) {
        self.interval = max(0.1, interval)
        self.maxSnapshots = maxSnapshots
    }
    
    // MARK: - Monitoring Control
    
    /// Start monitoring system performance
    public func start() {
        guard !isMonitoring else { return }
        
        isMonitoring = true
        
        monitoringTask = Task { [weak self] in
            guard let self = self else { return }
            
            while !Task.isCancelled {
                await self.collectSnapshot()
                try? await Task.sleep(nanoseconds: UInt64(self.interval * 1_000_000_000))
            }
        }
    }
    
    /// Stop monitoring
    public func stop() {
        monitoringTask?.cancel()
        monitoringTask = nil
        isMonitoring = false
    }
    
    /// Take a single snapshot without starting continuous monitoring
    public func snapshot() -> PerformanceSnapshot {
        createSnapshot()
    }
    
    // MARK: - Data Access
    
    /// Get the most recent snapshot
    public func latest() -> PerformanceSnapshot? {
        snapshots.last
    }
    
    /// Get snapshots within a time range
    public func snapshots(from start: Date, to end: Date) -> [PerformanceSnapshot] {
        snapshots.filter { $0.timestamp >= start && $0.timestamp <= end }
    }
    
    /// Get all collected snapshots
    public func allSnapshots() -> [PerformanceSnapshot] {
        snapshots
    }
    
    /// Calculate statistics for collected data
    public func statistics() -> PerformanceStatistics? {
        guard !snapshots.isEmpty else { return nil }
        
        let windowStart = snapshots.first!.timestamp
        let windowEnd = snapshots.last!.timestamp
        
        var totalCpu: Double = 0
        var peakCpu: Double = 0
        var totalMemory: UInt64 = 0
        var peakMemory: UInt64 = 0
        var totalGpu: Double = 0
        var peakGpu: Double = 0
        var gpuCount = 0
        var totalAne: Double = 0
        var peakAne: Double = 0
        var aneCount = 0
        var thermalThrottles = 0
        var memoryWarnings = 0
        
        for snapshot in snapshots {
            totalCpu += snapshot.cpuUsage
            peakCpu = max(peakCpu, snapshot.cpuUsage)
            
            totalMemory += snapshot.processMemoryUsage
            peakMemory = max(peakMemory, snapshot.processMemoryUsage)
            
            if let gpu = snapshot.gpuUsage {
                totalGpu += gpu
                peakGpu = max(peakGpu, gpu)
                gpuCount += 1
            }
            
            if let ane = snapshot.aneUsage {
                totalAne += ane
                peakAne = max(peakAne, ane)
                aneCount += 1
            }
            
            if snapshot.thermalState.shouldThrottle {
                thermalThrottles += 1
            }
            
            if snapshot.memoryPressure != .normal {
                memoryWarnings += 1
            }
        }
        
        let count = Double(snapshots.count)
        
        return PerformanceStatistics(
            windowStart: windowStart,
            windowEnd: windowEnd,
            sampleCount: snapshots.count,
            avgCpuUsage: totalCpu / count,
            peakCpuUsage: peakCpu,
            avgMemoryUsage: totalMemory / UInt64(snapshots.count),
            peakMemoryUsage: peakMemory,
            avgGpuUsage: gpuCount > 0 ? totalGpu / Double(gpuCount) : nil,
            peakGpuUsage: gpuCount > 0 ? peakGpu : nil,
            avgAneUsage: aneCount > 0 ? totalAne / Double(aneCount) : nil,
            peakAneUsage: aneCount > 0 ? peakAne : nil,
            thermalThrottleCount: thermalThrottles,
            memoryWarningCount: memoryWarnings
        )
    }
    
    /// Clear all collected snapshots
    public func clear() {
        snapshots.removeAll()
    }
    
    // MARK: - Event Handlers
    
    /// Register a handler for thermal state changes
    public func onThermalChange(_ handler: @escaping (ThermalState) -> Void) {
        thermalHandlers.append(handler)
    }
    
    /// Register a handler for memory pressure changes
    public func onMemoryPressure(_ handler: @escaping (MemoryPressure) -> Void) {
        memoryHandlers.append(handler)
    }
    
    // MARK: - Private Methods
    
    private func collectSnapshot() {
        let snapshot = createSnapshot()
        
        snapshots.append(snapshot)
        
        // Trim old snapshots
        if snapshots.count > maxSnapshots {
            snapshots.removeFirst(snapshots.count - maxSnapshots)
        }
        
        // Check for state changes
        if snapshot.thermalState != lastThermalState {
            lastThermalState = snapshot.thermalState
            for handler in thermalHandlers {
                handler(snapshot.thermalState)
            }
        }
        
        if snapshot.memoryPressure != lastMemoryPressure {
            lastMemoryPressure = snapshot.memoryPressure
            for handler in memoryHandlers {
                handler(snapshot.memoryPressure)
            }
        }
    }
    
    private func createSnapshot() -> PerformanceSnapshot {
        let thermalState = ThermalState(from: ProcessInfo.processInfo.thermalState)
        let memoryPressure = getMemoryPressure()
        let processMemory = getProcessMemoryUsage()
        let availableMemory = getAvailableMemory()
        let cpuUsage = getCPUUsage()
        let gpuUsage = getGPUUsage()
        let aneUsage = getANEUsage()
        let (batteryLevel, isPluggedIn) = getBatteryInfo()
        
        return PerformanceSnapshot(
            thermalState: thermalState,
            memoryPressure: memoryPressure,
            processMemoryUsage: processMemory,
            availableMemory: availableMemory,
            cpuUsage: cpuUsage,
            gpuUsage: gpuUsage,
            aneUsage: aneUsage,
            isLowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
            batteryLevel: batteryLevel,
            isPluggedIn: isPluggedIn
        )
    }
    
    private func getMemoryPressure() -> MemoryPressure {
        // Use dispatch source for memory pressure on macOS
        // For now, estimate based on available memory ratio
        let available = getAvailableMemory()
        let total = ProcessInfo.processInfo.physicalMemory
        let ratio = Double(available) / Double(total)
        
        if ratio > 0.3 {
            return .normal
        } else if ratio > 0.1 {
            return .warning
        } else {
            return .critical
        }
    }
    
    private func getProcessMemoryUsage() -> UInt64 {
        var info = task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(TASK_BASIC_INFO), $0, &count)
            }
        }
        
        if result == KERN_SUCCESS {
            return UInt64(info.resident_size)
        }
        
        return 0
    }
    
    private func getAvailableMemory() -> UInt64 {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        
        if result == KERN_SUCCESS {
            let pageSize = UInt64(vm_kernel_page_size)
            return UInt64(stats.free_count) * pageSize + UInt64(stats.inactive_count) * pageSize
        }
        
        return 0
    }
    
    private func getCPUUsage() -> Double {
        var threads: thread_act_array_t?
        var threadCount: mach_msg_type_number_t = 0
        
        let result = task_threads(mach_task_self_, &threads, &threadCount)
        
        guard result == KERN_SUCCESS, let threads = threads else {
            return 0
        }
        
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: threads), vm_size_t(Int(threadCount) * MemoryLayout<thread_t>.size))
        }
        
        var totalUsage: Double = 0
        
        for i in 0..<Int(threadCount) {
            var info = thread_basic_info()
            var count = mach_msg_type_number_t(MemoryLayout<thread_basic_info>.size / MemoryLayout<integer_t>.size)
            
            let infoResult = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                    thread_info(threads[i], thread_flavor_t(THREAD_BASIC_INFO), $0, &count)
                }
            }
            
            if infoResult == KERN_SUCCESS && (info.flags & TH_FLAGS_IDLE) == 0 {
                totalUsage += Double(info.cpu_usage) / Double(TH_USAGE_SCALE) * 100
            }
        }
        
        return min(100, totalUsage)
    }
    
    private func getGPUUsage() -> Double? {
        // GPU usage requires IOKit access which varies by device
        // Return nil for now - can be enhanced with actual GPU monitoring
        return nil
    }
    
    private func getANEUsage() -> Double? {
        // ANE usage monitoring requires private APIs
        // Return nil for now - can be enhanced with coremlprofiler integration
        return nil
    }
    
    private func getBatteryInfo() -> (level: Int?, isPluggedIn: Bool?) {
        #if os(iOS)
        UIDevice.current.isBatteryMonitoringEnabled = true
        let level = Int(UIDevice.current.batteryLevel * 100)
        let isPluggedIn = UIDevice.current.batteryState == .charging || UIDevice.current.batteryState == .full
        return (level >= 0 ? level : nil, isPluggedIn)
        #else
        // macOS battery info requires IOKit
        return (nil, nil)
        #endif
    }
}

// MARK: - Performance Monitor Extensions

extension PerformanceMonitor {
    
    /// Create an AsyncStream of performance snapshots
    public func snapshotStream() -> AsyncStream<PerformanceSnapshot> {
        AsyncStream { continuation in
            let task = Task {
                while !Task.isCancelled {
                    let snapshot = self.snapshot()
                    continuation.yield(snapshot)
                    try? await Task.sleep(nanoseconds: UInt64(self.interval * 1_000_000_000))
                }
                continuation.finish()
            }
            
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
    
    /// Run a profiling session for a specified duration
    public func profile(duration: TimeInterval) async -> PerformanceStatistics? {
        clear()
        start()
        
        try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
        
        stop()
        
        return statistics()
    }
}

// MARK: - Convenience

extension PerformanceSnapshot {
    /// Human-readable summary
    public var summary: String {
        var parts: [String] = []
        
        parts.append("Thermal: \(thermalState.rawValue)")
        parts.append("Memory: \(memoryPressure.rawValue)")
        parts.append(String(format: "CPU: %.1f%%", cpuUsage))
        
        let memoryMB = Double(processMemoryUsage) / 1_048_576
        parts.append(String(format: "RAM: %.0fMB", memoryMB))
        
        if let gpu = gpuUsage {
            parts.append(String(format: "GPU: %.1f%%", gpu))
        }
        
        if let ane = aneUsage {
            parts.append(String(format: "ANE: %.1f%%", ane))
        }
        
        if isLowPowerMode {
            parts.append("⚡️ Low Power")
        }
        
        return parts.joined(separator: " | ")
    }
}
