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
            AVVideoWidthKey: originalSize.width,
            AVVideoHeightKey: originalSize.height,
        ] as [String: Any]

    do {
        try FileManager.default.removeItem(at: outputURL)
    } catch {
        print("Could not remove file \(error.localizedDescription)")
    }

    guard let assetwriter = try? AVAssetWriter(outputURL: outputURL, fileType: .mov) else {
      abort()
    }
    
    let assetWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: assetWriterSettings)
    let assetWriterAdaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: assetWriterInput, sourcePixelBufferAttributes: nil)
    //add the input to the asset writer
    assetwriter.add(assetWriterInput)
    //begin the session
    assetwriter.startWriting()
    assetwriter.startSession(atSourceTime: CMTime.zero)
    //determine how many frames we need to generate
    let framesPerSecond = 30.0

    var pixelBuffer: CVPixelBuffer?
    
    for (frameIndex, detectionFrame) in detectionFrames.enumerated() {
        let renderer = UIGraphicsImageRenderer(size: originalSize)

        let image = renderer.image { context in
            context.cgContext.setLineWidth(4)
            context.cgContext.setStrokeColor(UIColor.green.cgColor)

            let rect = CGRect(
                x: detectionFrame.detection!.minX * originalSize.width,
                y: detectionFrame.detection!.minY * originalSize.height,
                width: detectionFrame.detection!.width * originalSize.width,
                height: detectionFrame.detection!.height * originalSize.height)

            context.stroke(rect)
        }

        var staticImage = CIImage(image: image)!

        let attrs =
            [
                kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue,
                kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue,
            ] as CFDictionary

        let width: Int = Int(staticImage.extent.size.width)
        let height: Int = Int(staticImage.extent.size.height)

        CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attrs,
            &pixelBuffer)
        //create a CIContext
        let bufferContext = CIContext()
        //use the context to render the image into the pixelBuffer
        bufferContext.render(staticImage, to: pixelBuffer!)
        
        if assetWriterInput.isReadyForMoreMediaData {
            let frameTime = CMTimeMake(value: Int64(frameIndex), timescale: Int32(framesPerSecond))
            //append the contents of the pixelBuffer at the correct time
            assetWriterAdaptor.append(pixelBuffer!, withPresentationTime: frameTime)
            
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
