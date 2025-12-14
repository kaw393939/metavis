import Foundation
import Dispatch

let args = Array(CommandLine.arguments.dropFirst())

Task {
    do {
        try await MetaVisLabProgram.run(args: args)
        exit(0)
    } catch {
        fputs("MetaVisLab failed: \(error)\n", stderr)
        exit(1)
    }
}

// Keep the process alive without blocking the main actor.
dispatchMain()
