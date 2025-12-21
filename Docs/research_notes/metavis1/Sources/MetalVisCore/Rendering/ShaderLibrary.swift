import Foundation
import Metal

/// Centralized repository for Metal shader functions.
///
/// The `ShaderLibrary` is responsible for loading, compiling, and caching Metal shader functions.
/// It provides a custom mechanism for handling `#include` directives in `.metal` files, which is
/// essential for modular shader development in Swift Package Manager environments where
/// standard `.metallib` linking can be problematic.
///
/// ## Features
/// - **Automatic Caching**: Compiled functions are cached to prevent redundant compilation.
/// - **Custom Preprocessor**: Resolves `#include` directives recursively.
/// - **Hot Reloading**: Supports loading raw source files for development iteration.
public class ShaderLibrary {
    private let device: MTLDevice
    private var library: MTLLibrary?
    private var functionCache: [String: MTLFunction] = [:]
    private let lock = NSLock()

    /// Initializes a new ShaderLibrary.
    /// - Parameter device: The Metal device to use for compilation.
    public init(device: MTLDevice) {
        self.device = device
        // Pre-compile all shaders from source since default.metallib is unreliable in SPM
        compileAllShadersFromSource()
    }
    
    private func compileAllShadersFromSource() {
        print("ShaderLibrary: Compiling all shaders from source...")
        let bundle = Bundle.module
        if let urls = bundle.urls(forResourcesWithExtension: "metal", subdirectory: nil) {
            for url in urls {
                let name = url.deletingPathExtension().lastPathComponent
                do {
                    try loadSource(resource: name)
                    print("ShaderLibrary: Successfully compiled \(name).metal")
                } catch {
                    print("ShaderLibrary: Failed to compile \(name).metal: \(error)")
                }
            }
        } else {
            print("ShaderLibrary: No .metal files found in bundle!")
        }
    }

    /// Load the default Metal library if not already loaded
    private func loadLibrary() throws -> MTLLibrary {
        if let library = library {
            return library
        }
        
        // Try to load from module bundle (SPM)
        if let bundlePath = Bundle.module.path(forResource: "default", ofType: "metallib") {
            let lib = try device.makeLibrary(URL: URL(fileURLWithPath: bundlePath))
            library = lib
            return lib
        }

        // Fallback to default library (App bundle)
        if let lib = device.makeDefaultLibrary() {
            library = lib
            return lib
        }

        throw ShaderLibraryError.libraryNotFound
    }

    /// Retrieve a shader function by name.
    ///
    /// This method first checks the cache. If the function is not found, it attempts to load
    /// it from the default library.
    ///
    /// - Parameter name: Name of the kernel, vertex, or fragment function.
    /// - Returns: The compiled `MTLFunction`.
    /// - Throws: `ShaderLibraryError.functionNotFound` if the function cannot be located.
    public func makeFunction(name: String) throws -> MTLFunction {
        lock.lock()
        defer { lock.unlock() }

        if let function = functionCache[name] {
            return function
        }

        // Try default library first
        if let library = try? loadLibrary(), let function = library.makeFunction(name: name) {
            functionCache[name] = function
            return function
        }

        throw ShaderLibraryError.functionNotFound(name)
    }

    /// Load a specific Metal source file (for development/hot-reloading).
    ///
    /// This method reads the `.metal` source file, resolves any `#include` directives
    /// using a custom preprocessor, compiles the source, and updates the function cache.
    ///
    /// - Parameter resource: Name of the .metal file in the bundle (without extension).
    /// - Throws: `ShaderLibraryError` if the source file is missing or compilation fails.
    public func loadSource(resource: String) throws {
        lock.lock()
        defer { lock.unlock() }

        let source = try loadSourceWithIncludes(resource: resource)
        let lib = try device.makeLibrary(source: source, options: nil)

        // Merge functions into cache
        for name in lib.functionNames {
            if let function = lib.makeFunction(name: name) {
                functionCache[name] = function
                print("ShaderLibrary: Cached function '\(name)'")
            }
        }
    }

    /// Recursively loads a Metal source file and resolves #include directives.
    ///
    /// - Parameter resource: The name of the resource to load.
    /// - Returns: The fully processed source code with includes expanded.
    private func loadSourceWithIncludes(resource: String) throws -> String {
        guard let bundlePath = Bundle.module.path(forResource: resource, ofType: "metal") else {
            throw ShaderLibraryError.sourceFileNotFound(resource)
        }

        let source = try String(contentsOfFile: bundlePath)
        
        // Simple regex to find #include "..."
        let includePattern = #"#include\s+"([^"]+)""#
        let regex = try NSRegularExpression(pattern: includePattern, options: [])
        
        var processedSource = source
        
        // Find all matches
        let matches = regex.matches(in: source, options: [], range: NSRange(location: 0, length: source.utf16.count))
        
        // Process in reverse to avoid invalidating ranges
        for match in matches.reversed() {
            if let range = Range(match.range, in: source),
               let fileRange = Range(match.range(at: 1), in: source) {
                let filename = String(source[fileRange])
                // Fix: Handle relative paths by using only the filename (assuming unique filenames)
                let resourceName = (filename as NSString).deletingPathExtension
                let simpleName = (resourceName as NSString).lastPathComponent
                
                // Recursively load included file
                if let includedSource = try? loadSourceWithIncludes(resource: simpleName) {
                    processedSource.replaceSubrange(range, with: includedSource)
                } else {
                    print("ShaderLibrary: Warning - Failed to resolve include '\(filename)'")
                }
            }
        }
        
        return processedSource
    }
}

public enum ShaderLibraryError: Error, LocalizedError {
    case libraryNotFound
    case functionNotFound(String)
    case sourceFileNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .libraryNotFound:
            return "Could not load default Metal library"
        case let .functionNotFound(name):
            return "Could not find shader function: \(name)"
        case let .sourceFileNotFound(name):
            return "Could not find Metal source file: \(name)"
        }
    }
}
