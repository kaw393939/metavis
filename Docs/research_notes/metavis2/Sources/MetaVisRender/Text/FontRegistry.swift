import CoreText
import Foundation

public enum FontError: Error {
    case fontNotFound(String)
    case invalidFontData
}

public class FontRegistry {
    private var fonts: [FontID: CTFont] = [:]
    private var nextID: FontID = 1
    private let lock = NSLock()
    
    public init() {}
    
    public func register(font: CTFont) -> FontID {
        lock.lock()
        defer { lock.unlock() }
        let id = nextID
        nextID += 1
        fonts[id] = font
        return id
    }
    
    public func register(name: String, size: CGFloat) throws -> FontID {
        let font = CTFontCreateWithName(name as CFString, size, nil)
        return register(font: font)
    }
    
    public func getFont(_ id: FontID) -> CTFont? {
        lock.lock()
        defer { lock.unlock() }
        return fonts[id]
    }
    
    public func unregister(_ id: FontID) {
        lock.lock()
        defer { lock.unlock() }
        fonts.removeValue(forKey: id)
    }
}
