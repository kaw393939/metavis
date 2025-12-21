// ExpressionEvaluator.swift
// MetaVisRender
//
// Created for Sprint 05: Timeline & Animation
// Math expression parser for dynamic animations

import Foundation

// MARK: - ExpressionEvaluator

/// Evaluates mathematical expressions for dynamic animation values.
/// Supports variables like `time`, `frame`, `progress` and functions like `sin`, `cos`, `lerp`.
public final class ExpressionEvaluator: @unchecked Sendable {
    
    // MARK: - Types
    
    /// Errors that can occur during expression evaluation
    public enum Error: Swift.Error, Equatable {
        case invalidExpression(String)
        case unknownFunction(String)
        case unknownVariable(String)
        case divisionByZero
        case invalidArguments(String)
        case syntaxError(String)
    }
    
    /// Token types for the lexer
    private enum Token: Equatable {
        case number(Double)
        case identifier(String)
        case plus
        case minus
        case multiply
        case divide
        case modulo
        case power
        case leftParen
        case rightParen
        case comma
        case eof
    }
    
    // MARK: - Built-in Functions
    
    /// Available mathematical functions
    private let functions: [String: ([Double]) throws -> Double] = [
        // Trigonometric
        "sin": { args in
            guard args.count == 1 else { throw Error.invalidArguments("sin requires 1 argument") }
            return sin(args[0])
        },
        "cos": { args in
            guard args.count == 1 else { throw Error.invalidArguments("cos requires 1 argument") }
            return cos(args[0])
        },
        "tan": { args in
            guard args.count == 1 else { throw Error.invalidArguments("tan requires 1 argument") }
            return tan(args[0])
        },
        "asin": { args in
            guard args.count == 1 else { throw Error.invalidArguments("asin requires 1 argument") }
            return asin(args[0])
        },
        "acos": { args in
            guard args.count == 1 else { throw Error.invalidArguments("acos requires 1 argument") }
            return acos(args[0])
        },
        "atan": { args in
            guard args.count == 1 else { throw Error.invalidArguments("atan requires 1 argument") }
            return atan(args[0])
        },
        "atan2": { args in
            guard args.count == 2 else { throw Error.invalidArguments("atan2 requires 2 arguments") }
            return atan2(args[0], args[1])
        },
        
        // Exponential
        "exp": { args in
            guard args.count == 1 else { throw Error.invalidArguments("exp requires 1 argument") }
            return exp(args[0])
        },
        "log": { args in
            guard args.count == 1 else { throw Error.invalidArguments("log requires 1 argument") }
            return log(args[0])
        },
        "log10": { args in
            guard args.count == 1 else { throw Error.invalidArguments("log10 requires 1 argument") }
            return log10(args[0])
        },
        "pow": { args in
            guard args.count == 2 else { throw Error.invalidArguments("pow requires 2 arguments") }
            return pow(args[0], args[1])
        },
        "sqrt": { args in
            guard args.count == 1 else { throw Error.invalidArguments("sqrt requires 1 argument") }
            return sqrt(args[0])
        },
        
        // Rounding
        "floor": { args in
            guard args.count == 1 else { throw Error.invalidArguments("floor requires 1 argument") }
            return floor(args[0])
        },
        "ceil": { args in
            guard args.count == 1 else { throw Error.invalidArguments("ceil requires 1 argument") }
            return ceil(args[0])
        },
        "round": { args in
            guard args.count == 1 else { throw Error.invalidArguments("round requires 1 argument") }
            return round(args[0])
        },
        "abs": { args in
            guard args.count == 1 else { throw Error.invalidArguments("abs requires 1 argument") }
            return abs(args[0])
        },
        
        // Clamping & Range
        "min": { args in
            guard args.count >= 2 else { throw Error.invalidArguments("min requires at least 2 arguments") }
            return args.min() ?? 0
        },
        "max": { args in
            guard args.count >= 2 else { throw Error.invalidArguments("max requires at least 2 arguments") }
            return args.max() ?? 0
        },
        "clamp": { args in
            guard args.count == 3 else { throw Error.invalidArguments("clamp requires 3 arguments (value, min, max)") }
            return Swift.min(Swift.max(args[0], args[1]), args[2])
        },
        
        // Interpolation
        "lerp": { args in
            guard args.count == 3 else { throw Error.invalidArguments("lerp requires 3 arguments (a, b, t)") }
            return args[0] + (args[1] - args[0]) * args[2]
        },
        "smoothstep": { args in
            guard args.count == 3 else { throw Error.invalidArguments("smoothstep requires 3 arguments (edge0, edge1, x)") }
            let edge0 = args[0]
            let edge1 = args[1]
            let x = args[2]
            let t = Swift.min(Swift.max((x - edge0) / (edge1 - edge0), 0), 1)
            return t * t * (3 - 2 * t)
        },
        "smootherstep": { args in
            guard args.count == 3 else { throw Error.invalidArguments("smootherstep requires 3 arguments (edge0, edge1, x)") }
            let edge0 = args[0]
            let edge1 = args[1]
            let x = args[2]
            let t = Swift.min(Swift.max((x - edge0) / (edge1 - edge0), 0), 1)
            return t * t * t * (t * (t * 6 - 15) + 10)
        },
        
        // Random (deterministic with seed)
        "random": { args in
            guard args.count == 1 else { throw Error.invalidArguments("random requires 1 argument (seed)") }
            // Simple hash-based pseudo-random
            let seed = args[0]
            var hash = seed * 12.9898 + 78.233
            hash = sin(hash) * 43758.5453
            return hash - floor(hash)
        },
        "noise": { args in
            guard args.count == 1 else { throw Error.invalidArguments("noise requires 1 argument") }
            // Simple 1D noise approximation
            let x = args[0]
            let i = floor(x)
            let f = x - i
            let u = f * f * (3 - 2 * f)
            
            let n0 = sin(i * 127.1) * 43758.5453
            let n1 = sin((i + 1) * 127.1) * 43758.5453
            let r0 = n0 - floor(n0)
            let r1 = n1 - floor(n1)
            
            return r0 * (1 - u) + r1 * u
        },
        
        // Animation helpers
        "pulse": { args in
            guard args.count == 3 else { throw Error.invalidArguments("pulse requires 3 arguments (time, frequency, width)") }
            let t = args[0]
            let freq = args[1]
            let width = args[2]
            let phase = (t * freq).truncatingRemainder(dividingBy: 1.0)
            return phase < width ? 1.0 : 0.0
        },
        "sawtooth": { args in
            guard args.count == 2 else { throw Error.invalidArguments("sawtooth requires 2 arguments (time, period)") }
            let t = args[0]
            let period = args[1]
            return (t / period).truncatingRemainder(dividingBy: 1.0)
        },
        "triangle": { args in
            guard args.count == 2 else { throw Error.invalidArguments("triangle requires 2 arguments (time, period)") }
            let t = args[0]
            let period = args[1]
            let phase = (t / period).truncatingRemainder(dividingBy: 1.0)
            return phase < 0.5 ? phase * 2 : 2 - phase * 2
        }
    ]
    
    // MARK: - Constants
    
    private let constants: [String: Double] = [
        "pi": .pi,
        "PI": .pi,
        "e": M_E,
        "tau": .pi * 2
    ]
    
    // MARK: - Parser State
    
    private var tokens: [Token] = []
    private var currentIndex: Int = 0
    private var context: TimelineResolver.Context?
    
    // MARK: - Initialization
    
    public init() {}
    
    // MARK: - Public API
    
    /// Evaluate an expression string with the given context
    public func evaluate(_ expression: String, context: TimelineResolver.Context) throws -> Double {
        self.context = context
        tokens = try tokenize(expression)
        currentIndex = 0
        return try parseExpression()
    }
    
    /// Evaluate an expression with custom variables
    public func evaluate(_ expression: String, variables: [String: Double]) throws -> Double {
        // Create a dummy context
        let ctx = TimelineResolver.Context(time: 0, frame: 0, duration: 1, fps: 30)
        self.context = ctx
        tokens = try tokenize(expression)
        currentIndex = 0
        
        // Override with custom variables during evaluation
        // This is handled in variableValue lookup
        return try parseExpression(customVariables: variables)
    }
    
    // MARK: - Lexer
    
    private func tokenize(_ expression: String) throws -> [Token] {
        var result: [Token] = []
        var index = expression.startIndex
        
        while index < expression.endIndex {
            let char = expression[index]
            
            // Skip whitespace
            if char.isWhitespace {
                index = expression.index(after: index)
                continue
            }
            
            // Number
            if char.isNumber || (char == "." && index < expression.index(before: expression.endIndex) && expression[expression.index(after: index)].isNumber) {
                var numStr = ""
                while index < expression.endIndex && (expression[index].isNumber || expression[index] == ".") {
                    numStr.append(expression[index])
                    index = expression.index(after: index)
                }
                guard let num = Double(numStr) else {
                    throw Error.syntaxError("Invalid number: \(numStr)")
                }
                result.append(.number(num))
                continue
            }
            
            // Identifier (variable or function)
            if char.isLetter || char == "_" {
                var identifier = ""
                while index < expression.endIndex && (expression[index].isLetter || expression[index].isNumber || expression[index] == "_") {
                    identifier.append(expression[index])
                    index = expression.index(after: index)
                }
                result.append(.identifier(identifier))
                continue
            }
            
            // Operators
            switch char {
            case "+": result.append(.plus)
            case "-": result.append(.minus)
            case "*": result.append(.multiply)
            case "/": result.append(.divide)
            case "%": result.append(.modulo)
            case "^": result.append(.power)
            case "(": result.append(.leftParen)
            case ")": result.append(.rightParen)
            case ",": result.append(.comma)
            default:
                throw Error.syntaxError("Unknown character: \(char)")
            }
            
            index = expression.index(after: index)
        }
        
        result.append(.eof)
        return result
    }
    
    // MARK: - Parser
    
    private var currentToken: Token {
        currentIndex < tokens.count ? tokens[currentIndex] : .eof
    }
    
    private func advance() {
        currentIndex += 1
    }
    
    private func parseExpression(customVariables: [String: Double] = [:]) throws -> Double {
        try parseAdditive(customVariables: customVariables)
    }
    
    private func parseAdditive(customVariables: [String: Double] = [:]) throws -> Double {
        var result = try parseMultiplicative(customVariables: customVariables)
        
        while true {
            switch currentToken {
            case .plus:
                advance()
                result += try parseMultiplicative(customVariables: customVariables)
            case .minus:
                advance()
                result -= try parseMultiplicative(customVariables: customVariables)
            default:
                return result
            }
        }
    }
    
    private func parseMultiplicative(customVariables: [String: Double] = [:]) throws -> Double {
        var result = try parsePower(customVariables: customVariables)
        
        while true {
            switch currentToken {
            case .multiply:
                advance()
                result *= try parsePower(customVariables: customVariables)
            case .divide:
                advance()
                let divisor = try parsePower(customVariables: customVariables)
                guard divisor != 0 else { throw Error.divisionByZero }
                result /= divisor
            case .modulo:
                advance()
                let divisor = try parsePower(customVariables: customVariables)
                guard divisor != 0 else { throw Error.divisionByZero }
                result = result.truncatingRemainder(dividingBy: divisor)
            default:
                return result
            }
        }
    }
    
    private func parsePower(customVariables: [String: Double] = [:]) throws -> Double {
        var result = try parseUnary(customVariables: customVariables)
        
        if case .power = currentToken {
            advance()
            let exponent = try parsePower(customVariables: customVariables)  // Right-associative
            result = pow(result, exponent)
        }
        
        return result
    }
    
    private func parseUnary(customVariables: [String: Double] = [:]) throws -> Double {
        switch currentToken {
        case .minus:
            advance()
            return try -parseUnary(customVariables: customVariables)
        case .plus:
            advance()
            return try parseUnary(customVariables: customVariables)
        default:
            return try parsePrimary(customVariables: customVariables)
        }
    }
    
    private func parsePrimary(customVariables: [String: Double] = [:]) throws -> Double {
        switch currentToken {
        case .number(let value):
            advance()
            return value
            
        case .identifier(let name):
            advance()
            
            // Check if it's a function call
            if case .leftParen = currentToken {
                return try parseFunctionCall(name: name, customVariables: customVariables)
            }
            
            // It's a variable
            return try variableValue(name: name, customVariables: customVariables)
            
        case .leftParen:
            advance()
            let result = try parseExpression(customVariables: customVariables)
            guard case .rightParen = currentToken else {
                throw Error.syntaxError("Expected closing parenthesis")
            }
            advance()
            return result
            
        default:
            throw Error.syntaxError("Unexpected token")
        }
    }
    
    private func parseFunctionCall(name: String, customVariables: [String: Double]) throws -> Double {
        guard case .leftParen = currentToken else {
            throw Error.syntaxError("Expected '(' after function name")
        }
        advance()
        
        var args: [Double] = []
        
        if case .rightParen = currentToken {
            advance()
        } else {
            args.append(try parseExpression(customVariables: customVariables))
            
            while case .comma = currentToken {
                advance()
                args.append(try parseExpression(customVariables: customVariables))
            }
            
            guard case .rightParen = currentToken else {
                throw Error.syntaxError("Expected ')' after function arguments")
            }
            advance()
        }
        
        guard let function = functions[name] else {
            throw Error.unknownFunction(name)
        }
        
        return try function(args)
    }
    
    private func variableValue(name: String, customVariables: [String: Double]) throws -> Double {
        // Check custom variables first
        if let value = customVariables[name] {
            return value
        }
        
        // Check constants
        if let value = constants[name] {
            return value
        }
        
        // Check context variables
        guard let ctx = context else {
            throw Error.unknownVariable(name)
        }
        
        switch name {
        case "time", "t":
            return ctx.time
        case "frame", "f":
            return Double(ctx.frame)
        case "duration":
            return ctx.duration
        case "progress", "p":
            return ctx.progress
        case "fps":
            return ctx.fps
        default:
            throw Error.unknownVariable(name)
        }
    }
}

// MARK: - Expression Presets

extension ExpressionEvaluator {
    /// Common expression patterns
    public enum Preset {
        /// Oscillating value: sin(time * frequency) * amplitude + offset
        case oscillate(frequency: Double, amplitude: Double, offset: Double)
        
        /// Fade in over duration
        case fadeIn(duration: Double)
        
        /// Fade out starting at time
        case fadeOut(startTime: Double, duration: Double)
        
        /// Pulse on/off
        case pulse(frequency: Double, dutyCycle: Double)
        
        /// Breathing effect (smooth oscillation)
        case breathe(frequency: Double, min: Double, max: Double)
        
        /// Random jitter
        case jitter(seed: Double, amount: Double)
        
        public var expression: String {
            switch self {
            case .oscillate(let freq, let amp, let offset):
                return "sin(time * \(freq) * 2 * pi) * \(amp) + \(offset)"
            case .fadeIn(let duration):
                return "clamp(time / \(duration), 0, 1)"
            case .fadeOut(let start, let duration):
                return "clamp(1 - (time - \(start)) / \(duration), 0, 1)"
            case .pulse(let freq, let duty):
                return "pulse(time, \(freq), \(duty))"
            case .breathe(let freq, let min, let max):
                let mid = (max + min) / 2
                let amp = (max - min) / 2
                return "sin(time * \(freq) * 2 * pi) * \(amp) + \(mid)"
            case .jitter(let seed, let amount):
                return "random(time * 1000 + \(seed)) * \(amount)"
            }
        }
    }
}
