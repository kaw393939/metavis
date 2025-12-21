import ArgumentParser
import Foundation
import Hummingbird
import Logging
import MetalVisCore
import NIOCore
import Shared

@main
@available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
struct MetalVisServerCommand: AsyncParsableCommand {
    @Option(name: .long, help: "Mode: 'server' or 'render'")
    var mode: String = "server"

    @Option(name: .long, help: "Path to manifest file (for render mode)")
    var manifest: String?

    @Option(name: .long, help: "Path to output file (for render mode)")
    var output: String?

    func run() async throws {
        let logger = Logger(label: "com.metalvis.server")

        // Auto-detect render mode if manifest is present
        if mode == "render" || manifest != nil {
            guard let manifestPath = manifest, let outputPath = output else {
                logger.error("Manifest and output paths are required for render mode")
                return
            }
            try await runRenderMode(manifestPath: manifestPath, outputPath: outputPath, logger: logger)
        } else {
            try await runServerMode(logger: logger)
        }
    }

    func runRenderMode(manifestPath: String, outputPath: String, logger: Logger) async throws {
        logger.info("Starting CLI render mode")
        // let coordinator = try RenderCoordinator()

        // Load render config
        // let renderConfig = RenderConfig.load()
        // await coordinator.updateConfig(renderConfig)

        // Load manifest
        // let url = URL(fileURLWithPath: manifestPath)
        // let data = try Data(contentsOf: url)
        // let composition = try JSONDecoder().decode(Composition.self, from: data)

        /*
        try await coordinator.renderComposition(
            composition: composition,
            outputPath: outputPath
        ) { progress, frame in
            if frame % 30 == 0 {
                print("Progress: \(Int(progress * 100))% (Frame \(frame))")
            }
        }
        */
        logger.info("Render complete (DISABLED)")
    }

    func runServerMode(logger: Logger) async throws {
        logger.info("Initializing JobQueue...")
        // Initialize job queue
        let jobQueue = try await JobQueue()
        logger.info("JobQueue initialized")

        // Create router
        let router = Router()

        // Health check
        router.get("/health") { _, _ -> ByteBuffer in
            return ByteBuffer(string: "OK")
        }

        // Submit render job
        router.post("/api/v1/render") { request, context -> ByteBuffer in
            do {
                let vizRequest = try await request.decode(as: VisualizationRequest.self, context: context)
                let job = await jobQueue.submitJob(vizRequest)

                let response = SubmitJobResponse(
                    jobId: job.id,
                    status: job.status.rawValue,
                    estimatedTime: vizRequest.outputConfig.duration
                )

                let responseData = try JSONEncoder().encode(response)
                return ByteBuffer(data: responseData)
            } catch {
                print("❌ Decode error: \(error)")
                if let decodingError = error as? DecodingError {
                    print("  Decoding error details: \(decodingError)")
                }
                let errorResponse = ErrorResponse(error: "Invalid request", details: "\(error)")
                let errorData = try! JSONEncoder().encode(errorResponse)
                return ByteBuffer(data: errorData)
            }
        }

        // Submit animated render job (narration-driven)
        router.post("/api/v1/render/animated") { request, context -> ByteBuffer in
            do {
                let animConfig = try await request.decode(as: MetalVisCore.AnimationConfig.self, context: context)
                let job = await jobQueue.submitAnimatedJob(animConfig)

                let response = SubmitJobResponse(
                    jobId: job.id,
                    status: job.status.rawValue,
                    estimatedTime: job.estimatedDuration
                )

                let responseData = try JSONEncoder().encode(response)
                return ByteBuffer(data: responseData)
            } catch {
                print("❌ Animated render decode error: \(error)")
                if let decodingError = error as? DecodingError {
                    print("  Decoding error details: \(decodingError)")
                }
                let errorResponse = ErrorResponse(error: "Invalid animated request", details: "\(error)")
                let errorData = try! JSONEncoder().encode(errorResponse)
                return ByteBuffer(data: errorData)
            }
        }

        // Submit Composition job
        router.post("/api/v1/render/composition") { request, context -> ByteBuffer in
            do {
                let composition = try await request.decode(as: Composition.self, context: context)
                let job = await jobQueue.submitCompositionJob(composition)

                let response = SubmitJobResponse(
                    jobId: job.id,
                    status: job.status.rawValue,
                    estimatedTime: composition.duration
                )

                let responseData = try JSONEncoder().encode(response)
                return ByteBuffer(data: responseData)
            } catch {
                print("❌ Composition decode error: \(error)")
                if let decodingError = error as? DecodingError {
                    print("  Decoding error details: \(decodingError)")
                }
                let errorResponse = ErrorResponse(error: "Invalid composition request", details: "\(error)")
                let errorData = try! JSONEncoder().encode(errorResponse)
                return ByteBuffer(data: errorData)
            }
        }

        // Submit image animation job (Ken Burns, zoom, pan, etc.)
        router.post("/api/v1/animate") { request, context -> ByteBuffer in
            do {
                let animRequest = try await request.decode(as: ImageAnimationRequest.self, context: context)
                let job = await jobQueue.submitImageAnimationJob(animRequest)

                let response = SubmitJobResponse(
                    jobId: job.id,
                    status: job.status.rawValue,
                    estimatedTime: animRequest.animation.duration
                )

                let responseData = try JSONEncoder().encode(response)
                return ByteBuffer(data: responseData)
            } catch {
                print("❌ Image animation decode error: \(error)")
                if let decodingError = error as? DecodingError {
                    print("  Decoding error details: \(decodingError)")
                }
                let errorResponse = ErrorResponse(error: "Invalid image animation request", details: "\(error)")
                let errorData = try! JSONEncoder().encode(errorResponse)
                return ByteBuffer(data: errorData)
            }
        }

        // Check job status
        router.get("/api/v1/render/{jobId}/status") { _, context -> ByteBuffer in
            guard let jobId = context.parameters.get("jobId") else {
                let errorResponse = ErrorResponse(error: "Missing job ID")
                let errorData = try! JSONEncoder().encode(errorResponse)
                return ByteBuffer(data: errorData)
            }

            guard let job = await jobQueue.getJob(id: jobId) else {
                let errorResponse = ErrorResponse(error: "Job not found")
                let errorData = try! JSONEncoder().encode(errorResponse)
                return ByteBuffer(data: errorData)
            }

            let elapsedTime = Date().timeIntervalSince(job.createdAt)
            let statusResponse = JobStatusResponse(
                jobId: job.id,
                status: job.status.rawValue,
                progress: job.progress,
                currentFrame: job.currentFrame,
                totalFrames: job.totalFrames,
                elapsedTime: elapsedTime,
                error: job.error
            )

            let responseData = try! JSONEncoder().encode(statusResponse)
            return ByteBuffer(data: responseData)
        }

        // Get job result
        router.get("/api/v1/render/{jobId}/result") { _, context -> ByteBuffer in
            guard let jobId = context.parameters.get("jobId") else {
                let errorResponse = ErrorResponse(error: "Missing job ID")
                let errorData = try! JSONEncoder().encode(errorResponse)
                return ByteBuffer(data: errorData)
            }

            guard let job = await jobQueue.getJob(id: jobId) else {
                let errorResponse = ErrorResponse(error: "Job not found")
                let errorData = try! JSONEncoder().encode(errorResponse)
                return ByteBuffer(data: errorData)
            }

            let renderTime = job.completedAt != nil ? job.completedAt!.timeIntervalSince(job.createdAt) : 0

            // Handle both static and animated jobs
            let (duration, resolution) = if let request = job.request {
                (request.outputConfig.duration, "\(request.outputConfig.resolution.width)x\(request.outputConfig.resolution.height)")
            } else {
                (job.estimatedDuration, "1920x1080") // Default for animated jobs
            }

            let resultResponse = JobResultResponse(
                jobId: job.id,
                status: job.status.rawValue,
                outputPath: job.outputPath,
                duration: duration,
                resolution: resolution,
                fileSize: job.outputPath != nil ? formatFileSize(job.outputPath!) : nil,
                renderTime: renderTime,
                error: job.error
            )

            let responseData = try! JSONEncoder().encode(resultResponse)
            return ByteBuffer(data: responseData)
        }

        // Download video
        router.get("/api/v1/render/{jobId}/download") { _, context -> Response in
            guard let jobId = context.parameters.get("jobId") else {
                return Response(status: .badRequest)
            }

            guard let job = await jobQueue.getJob(id: jobId),
                  let outputPath = job.outputPath
            else {
                return Response(status: .notFound)
            }

            let fileURL = URL(fileURLWithPath: outputPath)
            guard let data = try? Data(contentsOf: fileURL) else {
                return Response(status: .notFound)
            }

            return Response(
                status: .ok,
                headers: [
                    .contentType: "video/mp4",
                    .contentLength: "\(data.count)"
                ],
                body: .init(byteBuffer: ByteBuffer(data: data))
            )
        }

        // Build application
        let app = Application(
            router: router,
            configuration: .init(
                address: .hostname("127.0.0.1", port: 8080),
                serverName: "MetalVis"
            ),
            logger: logger
        )

        logger.info("MetalVis server starting on http://127.0.0.1:8080")

        try await app.runService()
    }
}

func formatFileSize(_ path: String) -> String? {
    guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
          let fileSize = attributes[.size] as? Int64
    else {
        return nil
    }

    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    return formatter.string(fromByteCount: fileSize)
}

// End of file
