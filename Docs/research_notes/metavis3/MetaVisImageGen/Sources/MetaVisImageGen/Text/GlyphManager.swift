import Metal
import CoreText
import Foundation

public class GlyphManager {
    private let device: MTLDevice
    private let fontRegistry: FontRegistry
    private let atlasBuilder: GlyphAtlasBuilder
    private let sdfGenerator: GlyphSDFGenerator
    private let cacheStore: GlyphCacheStore?
    private let scheduler = GlyphPipelineScheduler()
    
    // Runtime Cache: GlyphID -> GlyphAtlasLocation
    private var cache: [GlyphID: GlyphAtlasLocation] = [:]
    // Persisted Cache: StableGlyphKey -> GlyphAtlasLocation
    private var persistedEntries: [StableGlyphKey: GlyphAtlasLocation] = [:]
    // Pending Glyphs
    private var pending: Set<GlyphID> = []
    
    private let lock = NSLock()
    
    public init(device: MTLDevice, fontRegistry: FontRegistry) {
        self.device = device
        self.fontRegistry = fontRegistry
        self.atlasBuilder = GlyphAtlasBuilder(device: device)
        self.sdfGenerator = GlyphSDFGenerator()
        self.cacheStore = try? GlyphCacheStore()
        
        loadCache()
    }
    
    private func loadCache() {
        guard let store = cacheStore,
              let manifest = store.loadManifest(),
              let atlasState = manifest.atlasState else { return }
              
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm,
            width: atlasBuilder.size,
            height: atlasBuilder.size,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite]
        
        guard let texture = store.loadTexture(device: device, descriptor: descriptor) else { return }
        
        // Restore atlas
        // This happens on init, so no race condition yet
        atlasBuilder.restore(state: atlasState, texture: texture)
        self.persistedEntries = manifest.entries
        print("GlyphManager: Restored \(manifest.entries.count) glyphs from cache.")
    }
    
    public func getGlyph(id: GlyphID) -> GlyphAtlasLocation? {
        // Fast path: Check cache without blocking if possible, or just lock.
        lock.lock()
        if let cached = cache[id] {
            lock.unlock()
            return cached
        }
        
        // Check Persisted
        guard let font = fontRegistry.getFont(id.fontID) else {
            lock.unlock()
            return nil
        }
        
        let fontName = CTFontCopyPostScriptName(font) as String
        let fontSize = CTFontGetSize(font)
        let key = StableGlyphKey(fontName: fontName, fontSize: fontSize, glyphIndex: id.index)
        
        if let persisted = persistedEntries[key] {
            cache[id] = persisted
            lock.unlock()
            return persisted
        }
        
        // If we are here, we need to generate.
        // For Offline Rendering, we MUST block until it's done.
        // For Realtime, we would return nil and let it pop in later.
        // Let's implement a blocking generation for now to ensure correctness.
        
        let index = id.index
        let config = SDFConfiguration(fontSize: 64, padding: 8)
        
        // Unlock before generating to avoid deadlocks if we were using the scheduler
        lock.unlock()
        
        // Synchronous Generation
        if let result = self.sdfGenerator.generate(font: font, glyph: index, config: config) {
            lock.lock()
            defer { lock.unlock() }
            
            if let location = self.atlasBuilder.add(glyph: result) {
                self.cache[id] = location
                self.persistedEntries[key] = location
                return location
            }
        }
        
        return nil
    }
    
    public func saveCache() {
        // We should probably sync with atlas queue to ensure we don't save while writing
        scheduler.sync {
            lock.lock()
            defer { lock.unlock() }
            
            guard let store = cacheStore, let texture = atlasBuilder.texture else { return }
            
            let manifest = GlyphCacheManifest(
                version: 1,
                entries: persistedEntries,
                atlasState: atlasBuilder.getState()
            )
            
            store.saveManifest(manifest)
            store.saveTexture(texture)
        }
    }
    
    public func getTexture() -> MTLTexture? {
        if atlasBuilder.texture == nil {
            print("DEBUG: GlyphManager atlas is NIL")
        }
        return atlasBuilder.texture
    }
    
    public func getFont(id: FontID) -> CTFont? {
        return fontRegistry.getFont(id)
    }
}
