//
//  OverlayDetection.swift
//  TestPrediction
//
//  Created by Balogh Patrik on 2024. 10. 01..
//

import AVFoundation
import Vision
import UIKit

func overlayDetectionsOnVideo(
    inputURL: URL, detectionFrames: [DetectionFrame], outputURL: URL
) async throws -> URL {

    let originalVideo = AVURLAsset(url: inputURL)

    let composition = AVMutableComposition()

    guard
        let originalVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid)
    else {
        throw NSError(
            domain: "Cannot create composition video track", code: 0,
            userInfo: nil)
    }

    do {
        let timeRange = CMTimeRange(
            start: .zero, duration: try await originalVideo.load(.duration))

        try originalVideoTrack.insertTimeRange(
            timeRange,
            of: try await originalVideo.loadTracks(withMediaType: .video)[0],
            at: .zero)
    } catch {
        throw error
    }

    let originalSize = try await originalVideo.loadTracks(withMediaType: .video)
        .first!.load(.naturalSize)
    let transform = try await originalVideo.loadTracks(withMediaType: .video).first!.load(.preferredTransform)

    let width: Int = Int(originalSize.width)
    let height: Int = Int(originalSize.height)
    
    let orientedWidth = transform.a == 0 || transform.d == 0 ? height : width
    let orientedHeight = transform.a == 0 || transform.d == 0 ? width : height
    
    let assetWriterSettings =
        [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: orientedWidth,
            AVVideoHeightKey: orientedHeight,
        ] as [String: Any]

    do {
        try FileManager.default.removeItem(at: outputURL)
    } catch {
        print("Could not remove file \(error.localizedDescription)")
    }

    guard let assetwriter = try? AVAssetWriter(outputURL: outputURL, fileType: .mp4) else {
      abort()
    }
    
    
    
    let assetWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: assetWriterSettings)
    assetWriterInput.expectsMediaDataInRealTime = false
    assetwriter.add(assetWriterInput)
    
    let assetWriterAdaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: assetWriterInput, sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32ARGB),
        kCVPixelBufferWidthKey as String: orientedWidth,
        kCVPixelBufferHeightKey as String: orientedHeight
    ])
    
    
    assetwriter.startWriting()
    assetwriter.startSession(atSourceTime: CMTime.zero)
    let framesPerSecond = 30

    var pixelBuffer: CVPixelBuffer?

    
    for (frameIndex, detectionFrame) in detectionFrames.enumerated() {

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: orientedWidth,
            height: orientedHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else {
            print("Failed to create CGContext")
            return outputURL
        }
        
        context.setFillColor(CGColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1.0))
        context.fill(CGRect(x: 0, y: 0, width: orientedWidth, height: orientedHeight))
        
        
        let newBoundingBox = CGRect(x: detectionFrame.detection?.minX ?? 0, y: 1.0 - (detectionFrame.detection?.maxY ?? 0), width: detectionFrame.detection?.width ?? 0, height: detectionFrame.detection?.height ?? 0)
        
        let rect = VNImageRectForNormalizedRect(newBoundingBox,orientedWidth, orientedHeight)
        context.setStrokeColor(UIColor.green.cgColor)
        context.setLineWidth(4)
        context.stroke(rect)
        let cgImage = context.makeImage()!

        

        let presentationTime = CMTimeMake(value: Int64(frameIndex), timescale: Int32(framesPerSecond))
        let status = CVPixelBufferPoolCreatePixelBuffer(nil, assetWriterAdaptor.pixelBufferPool!, &pixelBuffer)
        if status == kCVReturnSuccess, let buffer = pixelBuffer {
            CVPixelBufferLockBaseAddress(buffer, .readOnly)
            let cicontext = CIContext()
            let ciImage = CIImage(cgImage: cgImage)
            cicontext.render(ciImage, to: buffer)
            assetWriterAdaptor.append(buffer, withPresentationTime: presentationTime)
            CVPixelBufferUnlockBaseAddress(buffer, .readOnly)
        } else {
            print("Failed to create or lock pixel buffer")
            
            return inputURL
        }
          
    }
    
    assetWriterInput.markAsFinished()
    assetwriter.finishWriting {
      pixelBuffer = nil
      //outputMovieURL now has the video
      print("Finished video location: \(outputURL)")
    }
    
    let rectangleVideo = AVURLAsset(url: outputURL)
    
    guard
        let rectangleVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid)
    else {
        throw NSError(
            domain: "Cannot create composition video track", code: 0,
            userInfo: nil)
    }

    do {
        let timeRange = CMTimeRange(
            start: .zero, duration: try await rectangleVideo.load(.duration))

        try rectangleVideoTrack.insertTimeRange(
            timeRange,
            of: try await originalVideo.loadTracks(withMediaType: .video)[0],
            at: .zero)
    } catch {
        throw error
    }
    
    let videoComposition = AVMutableVideoComposition()
    videoComposition.renderSize = CGSize(width: orientedWidth, height: orientedHeight)
        videoComposition.frameDuration = CMTimeMake(value: 1, timescale: 30)

    return outputURL
}
