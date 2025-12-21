import Foundation

public protocol RenderPipeline {
    func render(context: RenderContext) throws
}
