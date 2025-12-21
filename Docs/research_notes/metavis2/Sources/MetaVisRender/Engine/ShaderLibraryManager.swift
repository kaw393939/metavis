//
//  ShaderLibraryManager.swift
//  MetaVisRender
//
//  Manages separate shader libraries to avoid symbol conflicts
//  and enable modular shader development
//

import Metal
import Foundation

/// Manages multiple shader libraries with isolated namespaces
public class ShaderLibraryManager {
    private let device: MTLDevice
    private var libraries: [LibraryType: MTLLibrary] = [:]
    
    /// Types of shader libraries
    public enum LibraryType: String {
        case background = "Background"           // Solid, gradient, starfield backgrounds
        case procedural = "ProceduralField"     // Procedural noise fields, FBM nebula
        case postProcessing = "PostProcessing"  // Bloom, lens, depth of field (future)
        case compositing = "Compositing"        // Blend modes, masks (future)
        case text = "SDFText"                   // Text rendering
        
        var entryPoint: String {
            switch self {
            case .background: return "Background.metal"
            case .procedural: return "Procedural/ProceduralField.metal"
            case .postProcessing: return "PostProcessing.metal"
            case .compositing: return "Composite.metal"
            case .text: return "SDFText.metal"
            }
        }
    }
    
    public init(device: MTLDevice) {
        self.device = device
    }
    
    /// Load a shader library by type
    /// - Parameter type: The library type to load
    /// - Returns: Compiled Metal library
    /// - Throws: RenderError if library cannot be loaded
    public func loadLibrary(_ type: LibraryType) throws -> MTLLibrary {
        // Return cached if available
        if let cached = libraries[type] {
            return cached
        }
        
        // Try pre-compiled library first (production)
        if let precompiled = try? loadPrecompiledLibrary(type) {
            libraries[type] = precompiled
            return precompiled
        }
        
        // Fallback to runtime compilation (development)
        let compiled = try compileLibrary(type)
        libraries[type] = compiled
        return compiled
    }
    
    /// Attempt to load pre-compiled .metallib file
    private func loadPrecompiledLibrary(_ type: LibraryType) throws -> MTLLibrary? {
        // Try Bundle.module first
        if let lib = try? device.makeDefaultLibrary(bundle: Bundle.module) {
            // Verify it has the functions we need
            let requiredFunctions = getRequiredFunctions(for: type)
            if requiredFunctions.allSatisfy({ lib.functionNames.contains($0) }) {
                return lib
            }
        }
        return nil
    }
    
    /// Compile shader library from source at runtime
    private func compileLibrary(_ type: LibraryType) throws -> MTLLibrary {
        let compiler = ShaderCompiler(bundle: Bundle.module, rootDirectory: "Shaders")
        let source = try compiler.compile(file: type.entryPoint)
        
        do {
            return try device.makeLibrary(source: source, options: nil)
        } catch {
            throw RenderError.shaderCompilationFailed("\(type.rawValue): \(error.localizedDescription)")
        }
    }
    
    /// Get list of required function names for validation
    private func getRequiredFunctions(for type: LibraryType) -> [String] {
        switch type {
        case .background:
            return ["fx_solid_background", "fx_gradient_background", "fx_starfield_background"]
        case .procedural:
            return ["fx_procedural_field"]
        case .postProcessing:
            return ["composite", "compositeSimple"]
        case .compositing:
            return ["composite"]
        case .text:
            return ["sdf_text_vertex", "sdf_text_fragment"]
        }
    }
    
    /// Clear all cached libraries (useful for hot-reloading in development)
    public func clearCache() {
        libraries.removeAll()
    }
}
