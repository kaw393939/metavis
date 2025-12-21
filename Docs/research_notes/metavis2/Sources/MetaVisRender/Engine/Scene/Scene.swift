import Foundation

open class Scene {
    public var textElements: [TextElement] = []
    public var layers: [Layer] = []
    
    /// The active Virtual Camera for the scene
    public var virtualCamera: VirtualCamera = VirtualCamera()
    
    /// The Director's semantic schema (optional, for high-level control)
    public var directorSchema: DirectorSchema?
    
    /// Legacy Camera Definition (synced with virtualCamera)
    public var camera: CameraDefinition = CameraDefinition() {
        didSet {
            // Sync VirtualCamera when CameraDefinition changes
            virtualCamera.fov = camera.fov
            virtualCamera.position = camera.position
            virtualCamera.target = camera.target
        }
    }
    
    /// Procedural background (optional)
    public var proceduralBackground: BackgroundDefinition?
    
    // Store the original manifest camera for keyframe interpolation
    private var manifestCamera: CameraDefinition?
    
    public init() {}
    
    /// Sets the camera definition (including keyframes) from manifest
    public func setCamera(_ camera: CameraDefinition) {
        self.manifestCamera = camera
        self.camera = camera
    }
    
    open func update(time: Double) {
        // Interpolate camera keyframes if present
        if let mc = manifestCamera, mc.keyframes != nil {
            let (fov, position, target) = mc.interpolate(at: Float(time))
            // Create an updated camera definition with interpolated values
            camera = CameraDefinition(fov: fov, position: position, target: target)
        }
    }
}
