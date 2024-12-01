//
//  VideoDetailView.swift
//  TestPrediction
//
//  Created by Balogh Patrik on 2024. 11. 20..
//

import SwiftUI
import Vision

typealias DetectionFrame = (frameName: String, detection: CGRect?)

struct VideoDetailView: View {

    @State private var isProcessing = false
    @State private var isExporting = false
    @State private var processingProgress: Double = 0.0
    @State private var extractor: VideoFrameExtractor?
    @State private var detections: [DetectionFrame] = []
    @State private var extractedFramesCount: Int = 0

    let videoURL: URL
    private let predictionService: PredictionService = PredictionService()

    var body: some View {
        HStack {
            Text(videoURL.lastPathComponent)
        }
        Button("Process") {
            Task {
                await self.processVideo(url: videoURL)
            }
        }
        .buttonStyle(.bordered)

        if !isProcessing && extractedFramesCount > 0 {
            Button("Export Video") {
                Task {
                    await self.overlayVideo(videoURL, self.detections)
                }
            }
            .buttonStyle(.bordered)
        }

        if isProcessing || isExporting {
            let text = isProcessing ? "Processing..." : "Exporting..."
            ProgressView(text)
                .progressViewStyle(.circular)
                .padding()
        }

        if isProcessing {
            ProgressView(value: processingProgress, total: 1.0)
                .progressViewStyle(LinearProgressViewStyle())
                .padding()
            Text("\(Int(extractedFramesCount)) frames processed")

            Text("\(Int(processingProgress * 100))%")
                .font(.headline)
        }
        
        List(detections, id: \.frameName) { detection in
            Text("\(detection.frameName) - \(detection.detection ?? CGRect())")
        }
    }

    private func processVideo(url: URL) async {
        await MainActor.run {
            self.isProcessing = true
            self.processingProgress = 0.0
        }

        do {
            let extractor = try await VideoFrameExtractor(videoURL: url)
            self.extractor = extractor
            detections = []
            try await extractor.extractFrames {
                progress, extractedFrame, frameIndex in
                DispatchQueue.main.async {
                    self.processingProgress = progress
                    self.extractedFramesCount = frameIndex
                }

                let frameName = String(format: "frame%04d", frameIndex)

                if let frame = extractedFrame {
                    do {
                        let result = try self.predictionService.detectObjects(
                            in: frame)
                        if let detectionResult = result {
                            addDetection(frameName, detectionResult)
                        }
                    } catch {
                        print(
                            "Error processing frame: \(error.localizedDescription)"
                        )
                    }
                }

                if progress == 1.0 {
                    DispatchQueue.main.async {
                        self.isProcessing = false

                    }
                }
            }
        } catch {
            print("Error processing video: \(error.localizedDescription)")
            await MainActor.run {
                self.isProcessing = false
            }
        }
    }

    private func addDetection(
        _ frame: String, _ detectionResult: VNRecognizedObjectObservation
    ) {
        let boundingBox = detectionResult.boundingBox
        let newBoundingBox = CGRect(
            x: boundingBox.origin.y, y: boundingBox.origin.x,
            width: boundingBox.height, height: boundingBox.width)
        detections.append((frame, newBoundingBox))
    }

    private func overlayVideo(_ video: URL, _ detectionFrames: [DetectionFrame])
        async
    {
        isExporting = true
        guard
            let documentsDirectory = FileManager.default.urls(
                for: .documentDirectory, in: .userDomainMask
            ).first
        else {
            print("Error: Couldn't find documents directory")
            return
        }

        let outputURL = documentsDirectory.appendingPathComponent(
            "outputVideo.mp4")
        print("Output directory: \(outputURL.path)")
        print("Starting video processing...")

        do {
            let resultURL = try await overlayDetectionsOnVideo(
                inputURL: video, detectionFrames: detectionFrames,
                outputURL: outputURL)
            print("Video processing completed successfully")
            print("Output video saved at: \(resultURL.path)")
            isExporting = false
        } catch {
            isExporting = false
            print("Error processing video: \(error.localizedDescription)")
        }
    }

}

#Preview {
    let url = URL(string: "www.example.com")!

    VideoDetailView(videoURL: url)
}
