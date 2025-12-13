import Foundation

/// Schedules feature passes into a deterministic execution order based on named intermediate dependencies.
public struct PassScheduler: Sendable {
    public enum Error: Swift.Error, Sendable, Equatable {
        case duplicateOutputName(String)
        case cycleDetected
    }

    public init() {}

    /// Topologically sort passes based on dependencies inferred from `inputs` referring to other pass `output`s.
    ///
    /// - Note: Inputs that do not match any pass output are treated as external inputs.
    public func schedule(_ passes: [FeaturePass]) throws -> [FeaturePass] {
        guard passes.count > 1 else { return passes }

        var outputToIndex: [String: Int] = [:]
        outputToIndex.reserveCapacity(passes.count)

        for (i, pass) in passes.enumerated() {
            if outputToIndex[pass.output] != nil {
                throw Error.duplicateOutputName(pass.output)
            }
            outputToIndex[pass.output] = i
        }

        // Build dependency graph.
        var inDegree = Array(repeating: 0, count: passes.count)
        var edges: [[Int]] = Array(repeating: [], count: passes.count)

        for (i, pass) in passes.enumerated() {
            var deps = Set<Int>()
            for input in pass.inputs {
                if let dep = outputToIndex[input] {
                    deps.insert(dep)
                }
            }

            for dep in deps {
                edges[dep].append(i)
                inDegree[i] += 1
            }
        }

        // Kahn.
        var queue: [Int] = []
        queue.reserveCapacity(passes.count)
        for i in 0..<passes.count where inDegree[i] == 0 {
            queue.append(i)
        }

        var result: [FeaturePass] = []
        result.reserveCapacity(passes.count)

        var head = 0
        while head < queue.count {
            let u = queue[head]
            head += 1
            result.append(passes[u])

            for v in edges[u] {
                inDegree[v] -= 1
                if inDegree[v] == 0 {
                    queue.append(v)
                }
            }
        }

        guard result.count == passes.count else {
            throw Error.cycleDetected
        }

        return result
    }
}
