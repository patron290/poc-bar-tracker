//
//  OverlayDetection.swift
//  TestPrediction
//
//  Created by Balogh Patrik on 2024. 10. 01..
//

import AVFoundation
import UIKit

func overlayDetectionsOnVideo(
    inputURL: URL, detectionFrames: [DetectionFrame], outputURL: URL
) async throws -> URL {
    // Step 1: Create an AVAsset from the input URL
    let originalVideo = AVURLAsset(url: inputURL)

    // Step 2: Create an AVMutableComposition
    let composition = AVMutableComposition()

    guard
        let compositionVideoTrack = composition.addMutableTrack(
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

        try compositionVideoTrack.insertTimeRange(
            timeRange,
            of: try await originalVideo.loadTracks(withMediaType: .video)[0],
            at: .zero)
    } catch {
        throw error
    }

    let originalSize = try await originalVideo.loadTracks(withMediaType: .video)
        .first!.load(.naturalSize)
    let duration = try await originalVideo.load(.duration)

    let assetWriterSettings =
        [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: originalSize.height,
            AVVideoHeightKey: originalSize.width,
        ] as [String: Any]

    do {
        try FileManager.default.removeItem(at: outputURL)
    } catch {
        print("Could not remove file \(error.localizedDescription)")
    }

    guard let assetwriter = try? AVAssetWriter(outputURL: outputURL, fileType: .mov) else {
      abort()
    }
    
    // ORIENTATION!!!
    let width: Int = Int(originalSize.height)
    let height: Int = Int(originalSize.width)
    
    let assetWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: assetWriterSettings)
    assetWriterInput.expectsMediaDataInRealTime = false
    assetwriter.add(assetWriterInput)
    
    let assetWriterAdaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: assetWriterInput, sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32ARGB),
        kCVPixelBufferWidthKey as String: width,
        kCVPixelBufferHeightKey as String: height
    ])
    
    
    assetwriter.startWriting()
    assetwriter.startSession(atSourceTime: CMTime.zero)
    let framesPerSecond = 30

    var pixelBuffer: CVPixelBuffer?

    
    for (frameIndex, detectionFrame) in detectionFrames.enumerated() {

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else {
            print("Failed to create CGContext")
            return outputURL
        }
        
        context.setFillColor(CGColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1.0))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        
        
        let rect = CGRect(
                        x: detectionFrame.detection!.minX * originalSize.width,
                        y: detectionFrame.detection!.minY * originalSize.height,
                        width: detectionFrame.detection!.width * originalSize.width,
                        height: detectionFrame.detection!.height * originalSize.height)
        context.setStrokeColor(UIColor.green.cgColor)
        context.setLineWidth(4)
        context.stroke(rect)
        let cgImage = context.makeImage()!

        let presentationTime = CMTimeMake(value: Int64(frameIndex), timescale: Int32(framesPerSecond))
        let status = CVPixelBufferPoolCreatePixelBuffer(nil, assetWriterAdaptor.pixelBufferPool!, &pixelBuffer)
        if status == kCVReturnSuccess, let buffer = pixelBuffer {
            CVPixelBufferLockBaseAddress(buffer, .readOnly)
            let context = CIContext()
            let ciImage = CIImage(cgImage: cgImage)
            context.render(ciImage, to: buffer)
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

    return outputURL
}
