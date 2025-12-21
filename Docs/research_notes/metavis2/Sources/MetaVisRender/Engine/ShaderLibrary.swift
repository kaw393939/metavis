import Metal
import Foundation

public enum ShaderLibraryError: Error {
    case libraryNotFound
    case shaderSourceNotFound(String)
    case compilationFailed(String)
}

/// Manages the creation of Metal libraries, handling both pre-compiled and runtime-compiled shaders.
public final class ShaderLibrary {
    
    /// The shared default library.
    public static private(set) var defaultLibrary: MTLLibrary?
    
    /// Loads the default library.
    /// - Parameter device: The Metal device to use for compilation.
    /// - Returns: A compiled MTLLibrary.
    public static func loadDefaultLibrary(device: MTLDevice) throws -> MTLLibrary {
        if let library = defaultLibrary {
            return library
        }
        
        // 1. Try to load pre-compiled default.metallib (Production)
        // DEBUG: DISABLED to force runtime compilation and verify shader changes
        /* 
        if let library = try? device.makeDefaultLibrary(bundle: Bundle.module) {
            self.defaultLibrary = library
            print("DEBUG: Loaded pre-compiled default.metallib")
            return library
        }
        */
        print("DEBUG: Forcing Runtime Shader Compilation...")
        
        // 2. Fallback to Runtime Compilation (Development)
        let compiler = ShaderCompiler(bundle: Bundle.module, rootDirectory: "Shaders")
        
        // Define the core entry points we need to compile
        // We compile them into a single library to allow linking between them if needed
        // NOTE: FieldKernels.metal removed - has duplicate function names with Background.metal
        //       BackgroundPass uses Background.metal shaders instead
        //       ProceduralField.metal extracted from FieldKernels for fx_procedural_field kernel
        // NOTE: Modular shader architecture - each major subsystem loads its own library
        //       Background.metal - loaded by BackgroundPass
        //       ProceduralField.metal - loaded by ProceduralFieldPass  
        //       This prevents hash() redefinition and enables parallel shader development
        let entryPoints = [
            "ColorSpace.metal",
            "PostProcessing.metal",
            "SDFText.metal",
            "Debug.metal",
            "Composite.metal",         // Core compositing
            "DepthComposite.metal",    // AI depth compositing
            "IDT.metal",              // Sprint 19: Input/Output Device Transform
            "SpectralDispersion.metal", // Sprint 19: Prismatic light splitting
            "TextVisibilityAnalysis.metal", // Cinematic Title System
            "LightLeak.metal",        // Sprint 19: Film light leaks
            "Effects/ToneMapping.metal",  // Sprint 19: ACES tone mapping with correct color matrices
            "TextAnalysis.metal"       // Sprint 20: Cinematic Text Visibility
        ]
        
        var combinedSource = ""
        // Add common headers first if necessary, but the include resolver handles dependencies.
        
        for file in entryPoints {
            let source = try compiler.compile(file: file)
            combinedSource += "\n// --- Entry Point: \(file) ---\n"
            combinedSource += source
        }
        
        do {
            let library = try device.makeLibrary(source: combinedSource, options: nil)
            self.defaultLibrary = library
            return library
        } catch {
            throw ShaderLibraryError.compilationFailed(error.localizedDescription)
        }
    }
}

/// Handles the recursive resolution of #include directives for runtime Metal compilation.
class ShaderCompiler {
    let bundle: Bundle
    let rootDirectory: String
    
    // Tracks files that have already been included to prevent cycles and duplication
    private var includedFiles: Set<String> = []
    
    init(bundle: Bundle, rootDirectory: String) {
        self.bundle = bundle
        self.rootDirectory = rootDirectory
    }
    
    func compile(file: String) throws -> String {
        // Reset state for a new top-level compilation
        // Note: If we want to share includes across multiple entry points in one blob,
        // we should manage includedFiles externally or use #pragma once logic.
        // For now, we'll rely on the fact that we are concatenating entry points,
        // so we SHOULD reset, but internal includes (like ColorSpace.metal included by PostProcessing)
        // might be duplicated if we are not careful.
        //
        // Better approach: The 'combinedSource' in ShaderLibrary is one big file.
        // So we should NOT reset includedFiles if we share the compiler instance across the loop.
        // But here we create a new compiler or call compile multiple times?
        // Let's make compile() stateful for a session.
        
        return try resolveIncludes(file: file, currentDir: "")
    }
    
    private func resolveIncludes(file: String, currentDir: String) throws -> String {
        // 1. Resolve the full path relative to the bundle root
        // If 'file' is "Core/ACES.metal", it's relative to rootDirectory.
        // If 'file' is "ACES.metal" and currentDir is "Core", it's "Core/ACES.metal".
        
        var pathRelativeToRoot = file
        if !currentDir.isEmpty {
            pathRelativeToRoot = (currentDir as NSString).appendingPathComponent(file)
        }
        
        // Normalize
        pathRelativeToRoot = (pathRelativeToRoot as NSString).standardizingPath
        
        // 2. Check if already included (Pragma Once behavior)
        if includedFiles.contains(pathRelativeToRoot) {
            return "// [Skipped] Already included: \(pathRelativeToRoot)\n"
        }
        
        // 3. Locate file in Bundle
        guard let systemPath = bundle.path(forResource: pathRelativeToRoot, ofType: nil, inDirectory: rootDirectory) else {
            // Try looking in the root if not found in currentDir (Standard include path behavior)
            if let rootPath = bundle.path(forResource: file, ofType: nil, inDirectory: rootDirectory) {
                 // Found in root, update pathRelativeToRoot
                 pathRelativeToRoot = file
                 // Proceed with rootPath
                 return try processFile(systemPath: rootPath, pathRelativeToRoot: pathRelativeToRoot)
            }
            
            throw ShaderLibraryError.shaderSourceNotFound(pathRelativeToRoot)
        }
        
        return try processFile(systemPath: systemPath, pathRelativeToRoot: pathRelativeToRoot)
    }
    
    private func processFile(systemPath: String, pathRelativeToRoot: String) throws -> String {
        includedFiles.insert(pathRelativeToRoot)
        
        let content = try String(contentsOfFile: systemPath, encoding: .utf8)
        let currentDir = (pathRelativeToRoot as NSString).deletingLastPathComponent
        
        // DEBUG: Verify what we are reading
        if pathRelativeToRoot.contains("SDFText.metal") {
            print("DEBUG: [ShaderCompiler] Reading SDFText.metal from: \(systemPath)")
            print("DEBUG: [ShaderCompiler] Source Start:\n\(content.prefix(200))\n[End Snippet]")
        }
        
        var result = "// [Begin] \(pathRelativeToRoot)\n"
        
        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            if trimmed.hasPrefix("#include") {
                // Parse include
                if let range = trimmed.range(of: "\"(.*)\"", options: .regularExpression) {
                    let includeName = String(trimmed[range].dropFirst().dropLast())
                    
                    // Recursively resolve
                    let includedContent = try resolveIncludes(file: includeName, currentDir: currentDir)
                    result += includedContent
                } else if trimmed.contains("<") {
                    // System include (e.g. <metal_stdlib>) - keep as is
                    result += line + "\n"
                }
            } else {
                result += line + "\n"
            }
        }
        
        result += "// [End] \(pathRelativeToRoot)\n"
        return result
    }
}
