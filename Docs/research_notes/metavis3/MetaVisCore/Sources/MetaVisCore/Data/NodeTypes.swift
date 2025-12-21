import Foundation

/// Standard Node Types used across the system.
public enum NodeType {
    public static let source = "com.metavis.source"
    public static let videoSource = "com.metavis.source.video"
    public static let fitsSource = "com.metavis.source.fits"
    public static let text = "com.metavis.source.text"
    public static let generator = "com.metavis.source.generator"
    public static let audioWaveform = "com.metavis.source.audioWaveform"
    public static let output = "com.metavis.output"
    
    public enum Transition {
        public static let dissolve = "com.metavis.transition.dissolve"
        public static let wipe = "com.metavis.transition.wipe"
    }
    
    public enum Effect {
        public static let blur = "com.metavis.effect.blur"
        public static let colorGrade = "com.metavis.effect.colorGrade"
        public static let composite = "com.metavis.effect.composite"
        public static let jwstComposite = "com.metavis.effect.jwstComposite"
        public static let toneMap = "com.metavis.effect.toneMap"
        public static let acesOutput = "com.metavis.effect.acesOutput"
        public static let postProcess = "com.metavis.effect.postProcess"
        public static let blend = "com.metavis.effect.blend"
    }
}
