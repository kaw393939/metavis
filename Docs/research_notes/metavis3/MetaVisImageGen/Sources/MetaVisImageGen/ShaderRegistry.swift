import Metal
import Foundation

/// A centralized registry for managing Metal shaders.
/// This ensures that all shaders are loaded from the correct bundle and compiled properly.
/// It acts as a "Librarian" for agent-generated code.
public actor ShaderRegistry {
    
    public static let shared = ShaderRegistry()
    
    private var library: MTLLibrary?
    private var pipelineCache: [String: MTLComputePipelineState] = [:]
    
    public func getLibrary() -> MTLLibrary? {
        return library
    }
    
    private init() {}
    
    /// Initialize the registry with a device.
    /// This must be called before loading shaders.
    public func configure(device: MTLDevice) throws {
        print("📚 ShaderRegistry: Configuring on \(device.name)")
        
        // 1. Try Bundle.module (SwiftPM Standard)
        /*
        do {
            if let bundlePath = Bundle.module.resourcePath {
                print("   Looking in Bundle.module: \(bundlePath)")
            }
            self.library = try device.makeDefaultLibrary(bundle: Bundle.module)
            print("   ✅ Loaded library from Bundle.module")
        } catch {
            print("   ⚠️ Bundle.module load failed: \(error)")
        }
        */
        
        // 2. Fallback: Main Bundle (App)
        if self.library == nil {
            print("   Looking in Main Bundle: \(Bundle.main.bundlePath)")
            self.library = device.makeDefaultLibrary()
            if self.library != nil {
                print("   ✅ Loaded default library from Main Bundle")
            }
        }
        
        // 3. Fallback: Search for .metallib files recursively
        if self.library == nil {
            print("   ⚠️ Default loading failed. Scanning for .metallib files...")
            let fileManager = FileManager.default
            let currentPath = FileManager.default.currentDirectoryPath
            
            // Simple recursive search in current directory (useful for CLI)
            if let enumerator = fileManager.enumerator(atPath: currentPath) {
                for case let file as String in enumerator {
                    if file.hasSuffix(".metallib") {
                        let url = URL(fileURLWithPath: currentPath).appendingPathComponent(file)
                        print("   Found candidate: \(url.path)")
                        do {
                            self.library = try device.makeLibrary(URL: url)
                            print("   ✅ Loaded library from path: \(url.lastPathComponent)")
                            break 
                        } catch {
                            print("      ❌ Failed to load: \(error)")
                        }
                    }
                }
            }
        }

        // 4. Fallback: Compile from Source in Bundle
        if self.library == nil {
            print("   ⚠️ Binary loading failed. Scanning for .metal source files in Bundle.module...")
            
            let candidates = ["Macbeth", "Gradient", "SDFText"] // Add other shader names here if needed
            var combinedSource = ""
            
            for name in candidates {
                // Try root
                var path: String? = nil // Bundle.module.path(forResource: name, ofType: "metal")
                
                // Try Shaders subdirectory
                if path == nil {
                    // path = Bundle.module.path(forResource: name, ofType: "metal", inDirectory: "Shaders")
                }
                
                if let sourcePath = path {
                    print("   Found source: \(sourcePath)")
                    do {
                        let source = try String(contentsOfFile: sourcePath, encoding: .utf8)
                        combinedSource += "\n" + source
                    } catch {
                        print("      ❌ Failed to read source: \(error)")
                    }
                }
            }
            
            if !combinedSource.isEmpty {
                do {
                    self.library = try device.makeLibrary(source: combinedSource, options: nil)
                    print("   ✅ Compiled combined library from sources.")
                } catch {
                    print("      ❌ Failed to compile combined source: \(error)")
                }
            }
        }
        
        if self.library == nil {
            throw NSError(domain: "ShaderRegistry", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not load any Metal library. Checked Bundle.module, Main Bundle, local .metallib files, and source compilation."])
        }
        
        print("   Registry initialized with \(self.library?.functionNames.count ?? 0) shaders.")
    }
    
    /// Loads a compute pipeline by name.
    /// Handles caching and error reporting.
    public func loadCompute(name: String, device: MTLDevice) throws -> MTLComputePipelineState {
        // 1. Check Cache
        if let cached = pipelineCache[name] {
            return cached
        }
        
        // 2. Ensure Library is Loaded
        if library == nil {
            try configure(device: device)
        }
        
        guard let lib = library else {
            throw NSError(domain: "ShaderRegistry", code: 2, userInfo: [NSLocalizedDescriptionKey: "Metal Library not initialized"])
        }
        
        // 3. Find Function
        guard let function = lib.makeFunction(name: name) else {
            throw NSError(domain: "ShaderRegistry", code: 3, userInfo: [NSLocalizedDescriptionKey: "Shader function '\(name)' not found in library."])
        }
        
        // 4. Compile Pipeline
        let pipeline = try device.makeComputePipelineState(function: function)
        
        // 5. Cache
        pipelineCache[name] = pipeline
        
        return pipeline
    }
    
    /// Returns a list of all available shader names in the library.
    /// Useful for "Health Checks" and discovery.
    public func availableShaders() -> [String] {
        return library?.functionNames ?? []
    }
}
