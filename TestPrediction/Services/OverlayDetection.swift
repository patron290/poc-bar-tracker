//
//  OverlayDetection.swift
//  TestPrediction
//
//  Created by Balogh Patrik on 2024. 10. 01..
//

import AVFoundation
import UIKit

func overlayDetectionsOnVideo(inputURL: URL, detectionFrames: [DetectionFrame], outputURL: URL) async throws -> URL {
    // Step 1: Create an AVAsset from the input URL
    let asset = AVAsset(url: inputURL)
    
    // Step 2: Create an AVMutableComposition
    let composition = AVMutableComposition()
    
    // Add video track
    guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
        throw NSError(domain: "No video track", code: 0, userInfo: nil)
    }
    
    guard let compositionVideoTrack = composition.addMutableTrack(withMediaType: .video,
                                                                  preferredTrackID: kCMPersistentTrackID_Invalid) else {
        throw NSError(domain: "Cannot create composition video track", code: 0, userInfo: nil)
    }
    
    let duration = try await asset.load(.duration)
    do {
        try compositionVideoTrack.insertTimeRange(CMTimeRange(start: .zero, duration: duration),
                                                  of: videoTrack,
                                                  at: .zero)
    } catch {
        throw error
    }
    
    // Step 3: Create AVMutableVideoComposition
    let videoComposition = AVMutableVideoComposition()
    let nominalFrameRate = try await videoTrack.load(.nominalFrameRate)
    videoComposition.frameDuration = CMTimeMake(value: 1, timescale: Int32(nominalFrameRate))
    let naturalSize = try await videoTrack.load(.naturalSize)
    
    let preferredTransform = try await videoTrack.load(.preferredTransform)
    
    // Determine the video orientation and set renderSize accordingly
    var videoSize = naturalSize
    var isPortrait = false
    let angle = atan2(preferredTransform.b, preferredTransform.a) * 180 / .pi
    if angle == 90 || angle == -90 {
        isPortrait = true
        videoSize = CGSize(width: naturalSize.height, height: naturalSize.width)
    }
    
    videoComposition.renderSize = videoSize
    //videoComposition.renderSize = naturalSize
    
    // Step 4: Create overlay layers
    let overlayLayer = CALayer()
    overlayLayer.frame = CGRect(origin: .zero, size: naturalSize)
    
    let parentLayer = CALayer()
    let videoLayer = CALayer()
    parentLayer.frame = CGRect(origin: .zero, size: naturalSize)
    videoLayer.frame = CGRect(origin: .zero, size: naturalSize)
    
    parentLayer.addSublayer(videoLayer)
    parentLayer.addSublayer(overlayLayer)
    
    // Step 5: Create animation for detection rectangles
    let detectionLayer = CAShapeLayer()
    detectionLayer.frame = overlayLayer.bounds
    detectionLayer.fillColor = UIColor.clear.cgColor
    detectionLayer.strokeColor = UIColor.red.cgColor
    detectionLayer.lineWidth = 2.0
    detectionLayer.opacity = 1.0
    
    overlayLayer.addSublayer(detectionLayer)
    
    let pathAnimation = CAKeyframeAnimation(keyPath: "path")
    var times = [NSNumber]()
    var values = [CGPath]()
    
    let fps = nominalFrameRate
    let frameDuration = CMTimeMake(value: 1, timescale: Int32(fps))
    let totalFrames = Int(CMTimeGetSeconds(duration) * Double(fps))
    
    let testRect = CGRect(x: 100, y: 100, width: 200, height: 200) // Igazítsd a videó méretéhez szükség szerint
    let testPath = UIBezierPath(rect: testRect).cgPath
    times.append(0) // Kezdeti időpont
    values.append(testPath)
    
    for detectionFrame in detectionFrames {
        let frameIndexStr = detectionFrame.frameName
        let frameNumberStr = frameIndexStr.replacingOccurrences(of: "frame", with: "")
        if let frameNumber = Int(frameNumberStr) {
            let time = CMTimeMultiply(frameDuration, multiplier: Int32(frameNumber - 1))
            let timeInSeconds = CMTimeGetSeconds(time)
            let normalizedTime = timeInSeconds / CMTimeGetSeconds(duration)
            times.append(NSNumber(value: normalizedTime))
            
            if let detection = detectionFrame.detection {
                // Skalázás szükség szerint
                var scaledRect = CGRect(
                    x: detection.origin.x * naturalSize.width,
                    y: detection.origin.y * naturalSize.height,
                    width: detection.size.width * naturalSize.width,
                    height: detection.size.height * naturalSize.height
                )
                
                if isPortrait {
                   // Elforgatás, ha a videó portré orientációjú
                   let temp = scaledRect.origin.x
                   scaledRect.origin.x = scaledRect.origin.y
                   scaledRect.origin.y = videoSize.height - temp - scaledRect.height
               }
                let path = UIBezierPath(rect: scaledRect).cgPath
                values.append(path)
                print("Frame \(frameNumber): \(scaledRect)")
            } else {
                values.append(UIBezierPath().cgPath)
                print("Frame \(frameNumber): No detection")
            }
        }
    }
    
    guard !values.isEmpty else {
        throw NSError(domain: "No detection paths to animate", code: 0, userInfo: nil)
    }
    
    pathAnimation.keyTimes = times
    pathAnimation.values = values
    pathAnimation.duration = CMTimeGetSeconds(duration)
    pathAnimation.isRemovedOnCompletion = false
    pathAnimation.fillMode = .forwards
    detectionLayer.add(pathAnimation, forKey: "pathAnimation")
    
    // Set initial path
    if let firstPath = values.first {
        detectionLayer.path = firstPath
    }
    
    // Step 6: Apply animation tool
    videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(postProcessingAsVideoLayer: videoLayer, in: parentLayer)
    
    // Instruction
    let instruction = AVMutableVideoCompositionInstruction()
    instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
    let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionVideoTrack)
    layerInstruction.setTransform(preferredTransform, at: .zero)
    instruction.layerInstructions = [layerInstruction]
    videoComposition.instructions = [instruction]
    
    // Step 7: Export the video
    guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
        throw NSError(domain: "Export failed", code: 0, userInfo: nil)
    }
    
    exportSession.outputURL = outputURL
    exportSession.outputFileType = .mp4
    exportSession.videoComposition = videoComposition
    
    return try await withCheckedThrowingContinuation { continuation in
        exportSession.exportAsynchronously {
            switch exportSession.status {
            case .completed:
                if let outputURL = exportSession.outputURL {
                    continuation.resume(returning: outputURL)
                } else {
                    continuation.resume(throwing: NSError(domain: "Export failed", code: 0, userInfo: nil))
                }
            case .failed:
                if let error = exportSession.error {
                    print("Export failed with error: \(error.localizedDescription)")
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(throwing: NSError(domain: "Export failed", code: 0, userInfo: nil))
                }
            case .cancelled:
                continuation.resume(throwing: NSError(domain: "Export cancelled", code: 0, userInfo: nil))
            default:
                break
            }
        }
    }
}
