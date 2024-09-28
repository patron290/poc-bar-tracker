//
//  VideoConcat.swift
//  TestPrediction
//
//  Created by Balogh Patrik on 2024. 09. 08..
//

import AVFoundation
import UIKit

// Helper function to convert UIImage to CVPixelBuffer
func pixelBuffer(from image: UIImage, size: CGSize) -> CVPixelBuffer? {
    let attrs: [CFString: Any] = [
        kCVPixelBufferCGImageCompatibilityKey: true,
        kCVPixelBufferCGBitmapContextCompatibilityKey: true
    ]
    var pixelBuffer: CVPixelBuffer?
    let status = CVPixelBufferCreate(
        kCFAllocatorDefault,
        Int(size.width),
        Int(size.height),
        kCVPixelFormatType_32ARGB,
        attrs as CFDictionary,
        &pixelBuffer
    )
    
    guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
        return nil
    }
    
    CVPixelBufferLockBaseAddress(buffer, [])
    let pixelData = CVPixelBufferGetBaseAddress(buffer)
    
    let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: pixelData,
        width: Int(size.width),
        height: Int(size.height),
        bitsPerComponent: 8,
        bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
        space: rgbColorSpace,
        bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
    ) else {
        CVPixelBufferUnlockBaseAddress(buffer, [])
        return nil
    }
    
    // Ensure the image fits the video size
    UIGraphicsBeginImageContextWithOptions(size, false, 1.0)
    image.draw(in: CGRect(origin: .zero, size: size))
    let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
    UIGraphicsEndImageContext()
    
    if let resizedCGImage = resizedImage?.cgImage {
        context.draw(resizedCGImage, in: CGRect(origin: .zero, size: size))
    }
    
    CVPixelBufferUnlockBaseAddress(buffer, [])
    
    return buffer
}

func createVideo(from imagesDirectory: URL, outputURL: URL, frameRate: Int = 30, videoSize: CGSize) async throws {
    // Remove existing file if necessary
    if FileManager.default.fileExists(atPath: outputURL.path) {
        try FileManager.default.removeItem(at: outputURL)
    }
    
    // Initialize AVAssetWriter
    guard let writer = try? AVAssetWriter(outputURL: outputURL, fileType: .mov) else {
        throw NSError(domain: "AVAssetWriter", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unable to initialize AVAssetWriter"])
    }
    
    // Define video settings
    let videoSettings: [String: Any] = [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: videoSize.width,
        AVVideoHeightKey: videoSize.height
    ]
    
    // Initialize AVAssetWriterInput
    let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
    writerInput.expectsMediaDataInRealTime = false
    
    // Initialize AVAssetWriterInputPixelBufferAdaptor
    let sourcePixelBufferAttributes: [String: Any] = [
        kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32ARGB),
        kCVPixelBufferWidthKey as String: videoSize.width,
        kCVPixelBufferHeightKey as String: videoSize.height
    ]
    
    let pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
        assetWriterInput: writerInput,
        sourcePixelBufferAttributes: sourcePixelBufferAttributes
    )
    
    // Add input to writer
    guard writer.canAdd(writerInput) else {
        throw NSError(domain: "AVAssetWriter", code: -2, userInfo: [NSLocalizedDescriptionKey: "Cannot add input to AVAssetWriter"])
    }
    writer.add(writerInput)
    
    // Start writing session
    writer.startWriting()
    writer.startSession(atSourceTime: .zero)
    
    // Get sorted list of image URLs
    let fileURLs = try FileManager.default
        .contentsOfDirectory(at: imagesDirectory, includingPropertiesForKeys: nil)
        .filter { url in
            let ext = url.pathExtension.lowercased()
            return ext == "png" || ext == "jpg" || ext == "jpeg"
        }
        .sorted { $0.lastPathComponent < $1.lastPathComponent } // Sorting by filename
    
    let frameDuration = CMTime(value: 1, timescale: CMTimeScale(frameRate))
    
    let mediaInputQueue = DispatchQueue(label: "mediaInputQueue")
    
    writerInput.requestMediaDataWhenReady(on: mediaInputQueue) {
        for (index, fileURL) in fileURLs.enumerated() {
            if writerInput.isReadyForMoreMediaData {
                autoreleasepool {
                    do {
                        guard let image = UIImage(contentsOfFile: fileURL.path) else {
                            print("Failed to load image: \(fileURL.path)")
                            return
                        }
                        guard let pixelBuffer = pixelBuffer(from: image, size: videoSize) else {
                            print("Failed to create pixel buffer from image: \(fileURL.lastPathComponent)")
                            return
                        }
                        
                        let presentationTime = CMTimeMultiply(frameDuration, multiplier: Int32(index))
                        let success = pixelBufferAdaptor.append(pixelBuffer, withPresentationTime: presentationTime)
                        
                        if !success {
                            print("Failed to append pixel buffer at frame \(index)")
                        }
                        
                    } catch {
                        print("Error processing image \(fileURL.lastPathComponent): \(error.localizedDescription)")
                    }
                }
            }
        }
        
        writerInput.markAsFinished()
        writer.finishWriting {
            if writer.status == .completed {
                print("Video creation succeeded: \(outputURL)")
            } else {
                print("Video creation failed: \(writer.error?.localizedDescription ?? "Unknown error")")
            }
        }
    }
    
    // Wait until writing is finished
    while writer.status == .writing {
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
    }
    
    if writer.status != .completed {
        throw writer.error ?? NSError(domain: "AVAssetWriter", code: -3, userInfo: [NSLocalizedDescriptionKey: "Unknown error during video creation"])
    }
}
