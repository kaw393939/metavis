import Foundation
import simd

// MARK: - Text Animation Presets

/// Predefined text animation effects commonly used in film and video
public enum TextAnimationPreset: String, Codable, Sendable {
    // Classic Effects
    case none           // No animation
    case fadeIn         // Fade from transparent to opaque
    case fadeOut        // Fade from opaque to transparent
    case fadeInOut      // Fade in, hold, fade out
    
    // Movement Effects
    case crawlUp        // Star Wars style crawl (scrolls up with perspective)
    case crawlDown      // Reverse crawl (scrolls down)
    case slideInLeft    // Slide in from left
    case slideInRight   // Slide in from right
    case slideInUp      // Slide in from bottom
    case slideInDown    // Slide in from top
    case slideOutLeft   // Slide out to left
    case slideOutRight  // Slide out to right
    
    // Scale Effects
    case zoomIn         // Scale from small to normal
    case zoomOut        // Scale from normal to small
    case popIn          // Quick zoom with overshoot (bounce)
    case popOut         // Quick zoom out with anticipation
    
    // Reveal Effects
    case typewriter     // Characters appear one by one
    case wordByWord     // Words appear one by one
    case lineByLine     // Lines appear one by one
    
    // Cinematic Title Effects
    case titleCard      // Fade in, hold, fade out (classic title card)
    case lowerThird     // Slide in from side, hold, slide out
    case endCredits     // Slow scroll up (slower than crawl)
    case openingCrawl   // Full Star Wars style with perspective tilt
    
    // Dynamic Effects
    case bounce         // Bouncy entrance
    case shake          // Shake/vibrate effect
    case pulse          // Rhythmic scale pulsing
    case wave           // Characters wave up and down
    case glitch         // Digital glitch effect (position jitter)
}

// MARK: - Animation Configuration

/// Configuration for text animations
public struct TextAnimationConfig: Codable, Sendable {
    /// The animation preset to use
    public let preset: TextAnimationPreset
    
    /// When the animation starts (seconds from element start)
    public let delay: Float
    
    /// Duration of the animation (seconds)
    public let duration: Float
    
    /// Easing function name
    public let easing: String
    
    /// Speed multiplier for continuous animations (crawl, credits)
    public let speed: Float
    
    /// Hold time for in/out animations (seconds to hold at full visibility)
    public let holdDuration: Float
    
    /// Direction or angle for directional animations (degrees, 0 = right)
    public let direction: Float
    
    /// Loop the animation
    public let loop: Bool
    
    /// Reverse the animation on loop
    public let pingPong: Bool
    
    /// Per-character delay for typewriter-style effects (seconds)
    public let stagger: Float
    
    /// Custom parameters for specific animations
    public let parameters: [String: Float]
    
    public init(
        preset: TextAnimationPreset = .none,
        delay: Float = 0,
        duration: Float = 1.0,
        easing: String = "easeInOutCubic",
        speed: Float = 1.0,
        holdDuration: Float = 0,
        direction: Float = 0,
        loop: Bool = false,
        pingPong: Bool = false,
        stagger: Float = 0.05,
        parameters: [String: Float] = [:]
    ) {
        self.preset = preset
        self.delay = delay
        self.duration = duration
        self.easing = easing
        self.speed = speed
        self.holdDuration = holdDuration
        self.direction = direction
        self.loop = loop
        self.pingPong = pingPong
        self.stagger = stagger
        self.parameters = parameters
    }
    
    // MARK: - Preset Factories
    
    /// Star Wars opening crawl configuration
    public static func starWarsCrawl(speed: Float = 50.0) -> TextAnimationConfig {
        TextAnimationConfig(
            preset: .openingCrawl,
            duration: 0, // Continuous
            easing: "linear",
            speed: speed,
            parameters: [
                "perspectiveTilt": 60.0,  // Degrees of perspective tilt
                "vanishingPointY": 0.3,   // Where text vanishes (normalized)
                "fadeStartY": 0.4,        // Where fade begins (normalized)
                "fadeEndY": 0.2           // Where fully faded (normalized)
            ]
        )
    }
    
    /// End credits roll
    public static func endCredits(speed: Float = 30.0) -> TextAnimationConfig {
        TextAnimationConfig(
            preset: .endCredits,
            easing: "linear",
            speed: speed
        )
    }
    
    /// Classic title card (fade in, hold, fade out)
    public static func titleCard(fadeIn: Float = 1.0, hold: Float = 3.0, fadeOut: Float = 1.0) -> TextAnimationConfig {
        TextAnimationConfig(
            preset: .titleCard,
            duration: fadeIn,
            easing: "easeInOutCubic",
            holdDuration: hold,
            parameters: ["fadeOutDuration": fadeOut]
        )
    }
    
    /// Lower third graphic
    public static func lowerThird(direction: LowerThirdDirection = .left, duration: Float = 0.5, hold: Float = 5.0) -> TextAnimationConfig {
        TextAnimationConfig(
            preset: .lowerThird,
            duration: duration,
            easing: "easeOutCubic",
            holdDuration: hold,
            direction: direction == .left ? 180 : 0
        )
    }
    
    /// Typewriter effect
    public static func typewriter(charDelay: Float = 0.05) -> TextAnimationConfig {
        TextAnimationConfig(
            preset: .typewriter,
            easing: "linear",
            stagger: charDelay
        )
    }
    
    /// Pop-in effect with bounce
    public static func popIn(duration: Float = 0.4) -> TextAnimationConfig {
        TextAnimationConfig(
            preset: .popIn,
            duration: duration,
            easing: "easeOutBack"
        )
    }
    
    public enum LowerThirdDirection {
        case left, right
    }
}

// MARK: - Animation State

/// Computed animation state at a given time
public struct TextAnimationState {
    /// Position offset from base position
    public var positionOffset: SIMD3<Float> = .zero
    
    /// Scale factor (1.0 = normal)
    public var scale: Float = 1.0
    
    /// Opacity (0.0 = invisible, 1.0 = fully visible)
    public var opacity: Float = 1.0
    
    /// Rotation in degrees
    public var rotation: Float = 0
    
    /// Skew/shear for perspective effects
    public var skewX: Float = 0
    public var skewY: Float = 0
    
    /// For typewriter: how many characters to show (0 to text.count)
    public var visibleCharacters: Int = Int.max
    
    /// For per-character animations: offset per character index
    public var characterOffsets: [SIMD3<Float>]?
    
    /// Blur amount (0 = sharp)
    public var blur: Float = 0
    
    /// Combined with base position
    public func apply(to position: SIMD3<Float>) -> SIMD3<Float> {
        return position + positionOffset
    }
}

// MARK: - Animation Evaluator

/// Evaluates text animations to produce animation state
public class TextAnimationEvaluator {
    
    /// Evaluate animation state at a given time
    public static func evaluate(
        config: TextAnimationConfig,
        time: Float,
        elementDuration: Float,
        textLength: Int,
        viewportSize: SIMD2<Float>
    ) -> TextAnimationState {
        var state = TextAnimationState()
        
        // Apply delay
        let localTime = time - config.delay
        if localTime < 0 {
            // Before animation starts
            state.opacity = (config.preset == .fadeIn || config.preset == .fadeInOut || 
                            config.preset == .titleCard || config.preset == .popIn ||
                            config.preset == .zoomIn || config.preset == .typewriter ||
                            config.preset == .slideInLeft || config.preset == .slideInRight ||
                            config.preset == .slideInUp || config.preset == .slideInDown) ? 0 : 1
            state.visibleCharacters = (config.preset == .typewriter) ? 0 : Int.max
            return state
        }
        
        // Get easing function
        let easing = easingFromString(config.easing)
        
        switch config.preset {
        case .none:
            break
            
        case .fadeIn:
            let progress = clamp(localTime / config.duration, 0, 1)
            state.opacity = Float(easing.apply(Double(progress)))
            
        case .fadeOut:
            let progress = clamp(localTime / config.duration, 0, 1)
            state.opacity = 1.0 - Float(easing.apply(Double(progress)))
            
        case .fadeInOut:
            let totalDuration = config.duration * 2 + config.holdDuration
            if localTime < config.duration {
                // Fade in
                let progress = localTime / config.duration
                state.opacity = Float(easing.apply(Double(progress)))
            } else if localTime < config.duration + config.holdDuration {
                // Hold
                state.opacity = 1.0
            } else if localTime < totalDuration {
                // Fade out
                let fadeOutTime = localTime - config.duration - config.holdDuration
                let progress = fadeOutTime / config.duration
                state.opacity = 1.0 - Float(easing.apply(Double(progress)))
            } else {
                state.opacity = 0
            }
            
        case .crawlUp, .endCredits:
            let scrollSpeed = config.speed * (config.preset == .endCredits ? 0.5 : 1.0)
            state.positionOffset.y = -scrollSpeed * localTime
            
        case .crawlDown:
            state.positionOffset.y = config.speed * localTime
            
        case .openingCrawl:
            // Star Wars style: scroll + perspective
            let scrollSpeed = config.speed
            
            // Move along the tilted plane
            // We assume the text is rotated by 'perspectiveTilt' (e.g. -60 degrees)
            let tilt = config.parameters["perspectiveTilt"] ?? -60.0
            let rad = tilt * .pi / 180.0
            
            // Calculate movement vector along the plane's Y axis
            // If tilt is -60 (around X), local Y is (0, cos(-60), sin(-60)) = (0, 0.5, -0.866)
            let dy = cos(rad)
            let dz = sin(rad)
            
            state.positionOffset.y = scrollSpeed * localTime * dy
            state.positionOffset.z = scrollSpeed * localTime * dz
            
        case .slideInLeft:
            let progress = clamp(localTime / config.duration, 0, 1)
            let easedProgress = Float(easing.apply(Double(progress)))
            state.positionOffset.x = -viewportSize.x * (1.0 - easedProgress)
            state.opacity = easedProgress
            
        case .slideInRight:
            let progress = clamp(localTime / config.duration, 0, 1)
            let easedProgress = Float(easing.apply(Double(progress)))
            state.positionOffset.x = viewportSize.x * (1.0 - easedProgress)
            state.opacity = easedProgress
            
        case .slideInUp:
            let progress = clamp(localTime / config.duration, 0, 1)
            let easedProgress = Float(easing.apply(Double(progress)))
            state.positionOffset.y = viewportSize.y * (1.0 - easedProgress)
            state.opacity = easedProgress
            
        case .slideInDown:
            let progress = clamp(localTime / config.duration, 0, 1)
            let easedProgress = Float(easing.apply(Double(progress)))
            state.positionOffset.y = -viewportSize.y * (1.0 - easedProgress)
            state.opacity = easedProgress
            
        case .slideOutLeft:
            let progress = clamp(localTime / config.duration, 0, 1)
            let easedProgress = Float(easing.apply(Double(progress)))
            state.positionOffset.x = -viewportSize.x * easedProgress
            state.opacity = 1.0 - easedProgress
            
        case .slideOutRight:
            let progress = clamp(localTime / config.duration, 0, 1)
            let easedProgress = Float(easing.apply(Double(progress)))
            state.positionOffset.x = viewportSize.x * easedProgress
            state.opacity = 1.0 - easedProgress
            
        case .zoomIn:
            let progress = clamp(localTime / config.duration, 0, 1)
            let easedProgress = Float(easing.apply(Double(progress)))
            state.scale = easedProgress
            state.opacity = easedProgress
            
        case .zoomOut:
            let progress = clamp(localTime / config.duration, 0, 1)
            let easedProgress = Float(easing.apply(Double(progress)))
            state.scale = 1.0 - easedProgress * 0.5 // Don't go to zero
            state.opacity = 1.0 - easedProgress
            
        case .popIn:
            let progress = clamp(localTime / config.duration, 0, 1)
            let easedProgress = Float(easing.apply(Double(progress)))
            // Start from 0, overshoot to ~1.2, settle at 1.0 (easeOutBack handles this)
            state.scale = easedProgress
            state.opacity = min(easedProgress * 2, 1.0) // Fade in faster than scale
            
        case .popOut:
            let progress = clamp(localTime / config.duration, 0, 1)
            let easedProgress = Float(easing.apply(Double(progress)))
            state.scale = 1.0 - easedProgress
            state.opacity = 1.0 - easedProgress
            
        case .typewriter:
            // Characters revealed one by one
            let totalChars = textLength
            _ = config.stagger * Float(totalChars)  // totalTime reserved for future use
            let charsRevealed = Int(localTime / config.stagger)
            state.visibleCharacters = min(charsRevealed, totalChars)
            state.opacity = 1.0
            
        case .wordByWord:
            // Similar to typewriter but with words
            state.opacity = 1.0
            // Would need word count, simplified here
            state.visibleCharacters = Int(localTime / (config.stagger * 5)) * 5
            
        case .lineByLine:
            state.opacity = 1.0
            // Would need line count
            state.visibleCharacters = Int.max
            
        case .titleCard:
            let fadeInDuration = config.duration
            let fadeOutDuration = config.parameters["fadeOutDuration"] ?? config.duration
            let totalDuration = fadeInDuration + config.holdDuration + fadeOutDuration
            
            if localTime < fadeInDuration {
                let progress = localTime / fadeInDuration
                state.opacity = Float(easing.apply(Double(progress)))
            } else if localTime < fadeInDuration + config.holdDuration {
                state.opacity = 1.0
            } else if localTime < totalDuration {
                let fadeOutTime = localTime - fadeInDuration - config.holdDuration
                let progress = fadeOutTime / fadeOutDuration
                state.opacity = 1.0 - Float(easing.apply(Double(progress)))
            } else {
                state.opacity = 0
            }
            
        case .lowerThird:
            let slideIn = config.duration
            let slideOut = config.duration
            let totalDuration = slideIn + config.holdDuration + slideOut
            
            let fromLeft = config.direction > 90 && config.direction < 270
            let offscreenX = fromLeft ? -viewportSize.x * 0.3 : viewportSize.x * 0.3
            
            if localTime < slideIn {
                let progress = localTime / slideIn
                let easedProgress = Float(easing.apply(Double(progress)))
                state.positionOffset.x = offscreenX * (1.0 - easedProgress)
                state.opacity = easedProgress
            } else if localTime < slideIn + config.holdDuration {
                state.opacity = 1.0
            } else if localTime < totalDuration {
                let outTime = localTime - slideIn - config.holdDuration
                let progress = outTime / slideOut
                let easedProgress = Float(Easing.easeInCubic.apply(Double(progress)))
                state.positionOffset.x = offscreenX * easedProgress
                state.opacity = 1.0 - easedProgress
            } else {
                state.opacity = 0
            }
            
        case .bounce:
            let progress = clamp(localTime / config.duration, 0, 1)
            let easedProgress = Float(Easing.easeOutElastic.apply(Double(progress)))
            state.positionOffset.y = -50 * (1.0 - easedProgress)
            state.opacity = min(Float(progress) * 3, 1.0)
            
        case .shake:
            // Random-ish shake based on time
            let intensity: Float = 5.0
            let frequency: Float = 30.0
            state.positionOffset.x = sin(localTime * frequency) * intensity
            state.positionOffset.y = cos(localTime * frequency * 1.3) * intensity * 0.5
            
        case .pulse:
            let frequency: Float = 2.0 // Hz
            let amplitude: Float = 0.1
            state.scale = 1.0 + sin(localTime * frequency * 2 * .pi) * amplitude
            
        case .wave:
            // Per-character wave would need character offsets
            let frequency: Float = 3.0
            let amplitude: Float = 10.0
            state.positionOffset.y = sin(localTime * frequency * 2 * .pi) * amplitude
            
        case .glitch:
            // Random position jitter
            let shouldGlitch = Int(localTime * 10) % 7 == 0
            if shouldGlitch {
                state.positionOffset.x = Float.random(in: -10...10)
                state.positionOffset.y = Float.random(in: -5...5)
            }
        }
        
        return state
    }
    
    private static func clamp(_ value: Float, _ min: Float, _ max: Float) -> Float {
        return Swift.min(Swift.max(value, min), max)
    }
    
    private static func easingFromString(_ name: String) -> Easing {
        switch name.lowercased() {
        case "linear": return .linear
        case "easeinquad": return .easeInQuad
        case "easeoutquad": return .easeOutQuad
        case "easeinoutquad": return .easeInOutQuad
        case "easeincubic": return .easeInCubic
        case "easeoutcubic": return .easeOutCubic
        case "easeinoutcubic": return .easeInOutCubic
        case "easeoutback": return .easeOutBack
        case "easeoutelastic": return .easeOutElastic
        default: return .easeInOutCubic
        }
    }
}
