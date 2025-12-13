import Foundation

public enum MetaVisPerceptionError: Error, Sendable, CustomStringConvertible {
    case unsupportedGenericInfer(service: String, requestType: String, resultType: String)

    public var description: String {
        switch self {
        case let .unsupportedGenericInfer(service, requestType, resultType):
            return "\(service).infer(request:) is not supported for Request=\(requestType), Result=\(resultType). Use the service's explicit typed API instead."
        }
    }
}
