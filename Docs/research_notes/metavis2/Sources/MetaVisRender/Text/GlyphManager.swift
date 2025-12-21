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
        lock.lock()
        
        // 1. Check Cache
        if let cached = cache[id] {
            lock.unlock()
            return cached
        }
        
        // 2. Check Persisted Cache (Fast lookup)
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
        
        // 3. Check Pending
        if pending.contains(id) {
            lock.unlock()
            return nil // Still loading
        }
        
        // 4. Schedule Generation
        pending.insert(id)
        lock.unlock()
        
        let index = id.index
        // Increased padding to 8 to support larger shadows and thicker outlines
        let config = SDFConfiguration(fontSize: 64, padding: 8)
        
        scheduler.schedule(generationTask: { [weak self] in
            guard let self = self else { return nil }
            // This runs on concurrent background queue
            return self.sdfGenerator.generate(font: font, glyph: index, config: config)
        }, completion: { [weak self] result in
            guard let self = self else { return }
            // This runs on serial atlas queue
            
            // Add to Atlas
            guard let location = self.atlasBuilder.add(glyph: result) else {
                print("Atlas full!")
                return
            }
            
            // Update Cache (Thread Safe)
            self.lock.lock()
            self.cache[id] = location
            self.persistedEntries[key] = location
            self.pending.remove(id)
            self.lock.unlock()
        })
        
        // Check cache again (synchronous fallback)
        lock.lock()
        let result = cache[id]
        lock.unlock()
        return result
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
