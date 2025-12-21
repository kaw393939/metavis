// AI Vision Core Module
// Central documentation and namespace for AI components

/*
 AI Vision Core Components:
 
 ## Depth Estimation
 - `DepthMap` - Depth texture with metadata
 - `DepthEstimator` - Protocol for depth estimation
 - `MLDepthEstimator` - ML-based depth estimation with ANE support
 - `MockDepthEstimator` - Mock implementation for testing
 - `ComputeDevice` - CPU/GPU/ANE compute preference
 
 ## Vision Analysis
 - `VisionProvider` - Unified Vision framework integration
 - `SaliencyMap` / `SaliencyRegion` - Attention/objectness detection
 - `SegmentationMask` - Person segmentation
 - `OpticalFlow` - Motion detection
 - `SceneAnalysis` / `SceneType` - Scene classification
 
 ## Compositing
 - `DepthCompositor` - GPU depth-aware compositing
 - `CompositeMode` - behindSubject, inFrontOfAll, depthSorted, parallax
 
 ## Layout
 - `TextLayoutPlanner` - AI-powered text placement
 - `TextPlacement` - Optimal placement result
 - `LayoutHint` - AI analysis hints
 
 ## Usage Example:
 ```swift
 // 1. Create components
 let depthEstimator = try MLDepthEstimator(device: device)
 let visionProvider = VisionProvider(device: device)
 let compositor = try DepthCompositor(device: device)
 let layoutPlanner = TextLayoutPlanner()
 
 // 2. Analyze frame
 let depthMap = try await depthEstimator.estimateDepth(from: videoTexture)
 let saliency = try await visionProvider.detectSaliency(in: videoTexture)
 
 // 3. Find optimal placement
 let placement = try await layoutPlanner.findOptimalPlacement(
     for: "Hello World",
     saliency: saliency,
     segmentation: nil,
     frameSize: CGSize(width: 1920, height: 1080)
 )
 
 // 4. Composite with depth
 let result = try await compositor.composite(
     text: textTexture,
     video: videoTexture,
     depth: depthMap,
     mode: .behindSubject
 )
 ```
 */

// Type aliases for convenience (optional - types are already public)
public typealias AIDepthMap = DepthMap
public typealias AIVisionProvider = VisionProvider
public typealias AIDepthCompositor = DepthCompositor
public typealias AITextLayoutPlanner = TextLayoutPlanner

