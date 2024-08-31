import Foundation
import AVFoundation
import UIKit

class VideoFrameExtractor {
    private let videoAsset: AVAsset
    private var framesExtracted = 0
    private var totalFrames: Int
    private var assetReader: AVAssetReader?
    
    init(videoURL: URL) async throws {
        self.videoAsset = AVAsset(url: videoURL)
        guard let track = try await self.videoAsset.loadTracks(withMediaType: .video).first else {
            throw NSError(domain: "VideoFrameExtractor", code: 0, userInfo: [NSLocalizedDescriptionKey: "No video track found"])
        }
        let duration = try await videoAsset.load(.duration)
        let nominalFrameRate = try await track.load(.nominalFrameRate)
        self.totalFrames = Int(CMTimeGetSeconds(duration) * Float64(nominalFrameRate))
    }
    
    func extractFrames(completion: @escaping ( Double, CGImage?) -> Void) async throws {
        guard let track = try await self.videoAsset.loadTracks(withMediaType: .video).first else {
            throw NSError(domain: "VideoFrameExtractor", code: 0, userInfo: [NSLocalizedDescriptionKey: "No video track found"])
        }
        
        let outputSettings: [String: Any] = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        let assetReaderOutput = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        
        self.assetReader = try AVAssetReader(asset: self.videoAsset)
        guard let assetReader = self.assetReader else {
            throw NSError(domain: "VideoFrameExtractor", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create asset reader"])
        }
        
        assetReader.add(assetReaderOutput)
        assetReader.startReading()
        
        let context = CIContext()
        
        let resizeFilter = CIFilter(name:"CILanczosScaleTransform")!
        
        DispatchQueue.global(qos: .userInitiated).async {
            while assetReader.status == .reading {
                autoreleasepool {
                    guard let sampleBuffer = assetReaderOutput.copyNextSampleBuffer(),
                          let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                        return
                    }
                    
                    self.framesExtracted += 1
                    let progress = Double(self.framesExtracted) / Double(self.totalFrames)
                    
                    let ciImage = CIImage(cvPixelBuffer: imageBuffer)
                    
                    //let scale = targetSize.height / (ciImage.extent.height)
                    //let aspectRatio = targetSize.width/((ciImage.extent.width) * scale)

                    // Apply resizing
                    resizeFilter.setValue(ciImage, forKey: kCIInputImageKey)
                    resizeFilter.setValue(1.0, forKey: kCIInputScaleKey)
                    //resizeFilter.setValue(aspectRatio, forKey: kCIInputAspectRatioKey)
                    let outputImage = resizeFilter.outputImage
                    
                    let cgImage = context.createCGImage(outputImage!, from: outputImage!.extent)
                    //let cgImage = context.createCGImage(ciImage, from: ciImage.extent)
                    
                    if let cgImage = context.createCGImage(outputImage!, from: outputImage!.extent) {
                        DispatchQueue.main.async {
                            completion(progress, cgImage)
                        }
                    }
//                    if let cgImage = context.createCGImage(ciImage, from: ciImage.extent) {
//                        //let image = UIImage(cgImage: cgImage,scale: 1.0, orientation: .right)
//                    }
                    
                }
            }
        }
        
        if assetReader.status == .completed {
            DispatchQueue.main.async {
                            completion(1.0, nil)
                        }
        } else if assetReader.status == .failed {
            DispatchQueue.main.async {
                            completion(1.0, nil)
                        }
            throw assetReader.error ?? NSError(domain: "VideoFrameExtractor", code: 2, userInfo: [NSLocalizedDescriptionKey: "Asset reader failed"])
        }
    }
    
    func cancelExtraction() {
        self.assetReader?.cancelReading()
    }
}
