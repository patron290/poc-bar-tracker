import Foundation
import AVFoundation
import UIKit

class VideoFrameExtractor {
    private let videoAsset: AVAsset
    private var framesExtracted = 0
    private var totalFrames: Int
    private var assetReader: AVAssetReader?
    private let context = CIContext()
    
    init(videoURL: URL) async throws {
        self.videoAsset = AVAsset(url: videoURL)
        guard let track = try await self.videoAsset.loadTracks(withMediaType: .video).first else {
            throw NSError(domain: "VideoFrameExtractor", code: 0, userInfo: [NSLocalizedDescriptionKey: "No video track found"])
        }
        let duration = try await videoAsset.load(.duration)
        let nominalFrameRate = try await track.load(.nominalFrameRate)
        self.totalFrames = Int(CMTimeGetSeconds(duration) * Float64(nominalFrameRate))
    }
    
    func extractFrames(completion: @escaping ( Double, CGImage?, Int) -> Void) async throws {
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
                    let frameIndex = self.framesExtracted
                    
                    let ciImage = CIImage(cvPixelBuffer: imageBuffer)
                    
                    resizeFilter.setValue(ciImage, forKey: kCIInputImageKey)
                    resizeFilter.setValue(0.4, forKey: kCIInputScaleKey)
                    let outputImage = resizeFilter.outputImage
                    
                    let cgImage = self.context.createCGImage(outputImage!, from: outputImage!.extent)
                    
                    if let cgImage = self.context.createCGImage(outputImage!, from: outputImage!.extent) {
                        DispatchQueue.main.async {
                            completion(progress, cgImage, frameIndex)
                        }
                    }
                }
            }
        }
        
        if assetReader.status == .completed {
            DispatchQueue.main.async {
                completion(1.0, nil, self.framesExtracted)
                        }
        } else if assetReader.status == .failed {
            DispatchQueue.main.async {
                completion(1.0, nil, self.framesExtracted)
                        }
            throw assetReader.error ?? NSError(domain: "VideoFrameExtractor", code: 2, userInfo: [NSLocalizedDescriptionKey: "Asset reader failed"])
        }
    }
    
    func cancelExtraction() {
        self.assetReader?.cancelReading()
    }
}
