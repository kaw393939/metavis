import Foundation
import Metal

final class TexturePool {
    struct Key: Hashable {
        let width: Int
        let height: Int
        let pixelFormat: MTLPixelFormat
        let mipLevelCount: Int
        let usageRaw: UInt64
        let storageModeRaw: UInt64
    }

    private let device: MTLDevice
    private var buckets: [Key: [MTLTexture]] = [:]
    private var knownTextures: Set<ObjectIdentifier> = []

    init(device: MTLDevice) {
        self.device = device
    }

    func checkout(
        width: Int,
        height: Int,
        pixelFormat: MTLPixelFormat,
        usage: MTLTextureUsage,
        storageMode: MTLStorageMode = .private,
        mipmapped: Bool = false,
        mipLevelCount: Int? = nil
    ) -> MTLTexture? {
        let resolvedMipLevels: Int = {
            if let mipLevelCount { return max(1, mipLevelCount) }
            if mipmapped {
                // Full mip chain for the given dimensions.
                let m = max(width, height)
                return max(1, Int(floor(log2(Double(max(1, m))))) + 1)
            }
            return 1
        }()

        let key = Key(
            width: width,
            height: height,
            pixelFormat: pixelFormat,
            mipLevelCount: resolvedMipLevels,
            usageRaw: UInt64(usage.rawValue),
            storageModeRaw: UInt64(storageMode.rawValue)
        )

        if var bucket = buckets[key], let tex = bucket.popLast() {
            buckets[key] = bucket
            return tex
        }

        let desc: MTLTextureDescriptor
        if resolvedMipLevels > 1 {
            desc = MTLTextureDescriptor()
            desc.textureType = .type2D
            desc.pixelFormat = pixelFormat
            desc.width = width
            desc.height = height
            desc.mipmapLevelCount = resolvedMipLevels
        } else {
            desc = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: pixelFormat,
                width: width,
                height: height,
                mipmapped: false
            )
        }
        desc.usage = usage
        desc.storageMode = storageMode

        guard let tex = device.makeTexture(descriptor: desc) else { return nil }
        MetalSimulationDiagnostics.incrementTextureAllocation()
        knownTextures.insert(ObjectIdentifier(tex))
        return tex
    }

    func checkin(_ texture: MTLTexture) {
        let oid = ObjectIdentifier(texture)
        guard knownTextures.contains(oid) else { return }

        let mipLevels = max(1, texture.mipmapLevelCount)
        let key = Key(
            width: texture.width,
            height: texture.height,
            pixelFormat: texture.pixelFormat,
            mipLevelCount: mipLevels,
            usageRaw: UInt64(texture.usage.rawValue),
            storageModeRaw: UInt64(texture.storageMode.rawValue)
        )
        buckets[key, default: []].append(texture)
    }

    func purge() {
        buckets.removeAll()
    }
}
