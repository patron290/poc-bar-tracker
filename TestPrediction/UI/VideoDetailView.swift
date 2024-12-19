//
//  VideoDetailView.swift
//  TestPrediction
//
//  Created by Balogh Patrik on 2024. 11. 20..
//

import CoreData
import SwiftUI
import Vision

typealias DetectionFrame = (frameName: String, detection: CGRect?)

struct VideoDetailView: View {
    @Environment(\.managedObjectContext) private var viewContext

    @State private var isProcessing = false
    @State private var isExporting = false
    @State private var processingProgress: Double = 0.0
    @State private var extractor: VideoFrameExtractor?
    @State private var detections: [DetectionFrame] = []
    @State private var extractedFramesCount: Int = 0
    var videoEntity: VideoEntity
    @State private var predictions: [PredictionResultEntity] = []

    private let predictionService: PredictionService = PredictionService()

    var body: some View {
        HStack {
            Text(videoEntity.videoName ?? "Missing name")
            Text("\(videoEntity.videoUrl!)")
        }
        Button("Process") {
            Task {
                await self.processVideo(url: videoEntity.videoUrl!)
            }
        }
        .buttonStyle(.bordered)

        if let detections = videoEntity.predictions, detections.count > 0 && !isProcessing && !isExporting {
            Button("Export Video") {
                Task {
                    await self.overlayVideo(videoEntity)
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

        if let predictionsSet = videoEntity.predictions
            as? Set<PredictionResultEntity>
        {
            let predictions = predictionsSet.sorted(by: { $0.x < $1.x })

            if !predictions.isEmpty {
                List {
                    ForEach(predictions, id: \.self) { prediction in
                        HStack {
                            Text("\(prediction.frameIndex)")
                            Text("\(prediction.x)")
                                .font(.headline)
                            Text("\(prediction.y)")
                                .font(.headline)
                        }
                    }
                }
            } else {
                Text("No predictions found.")
            }
        } else {
            Text("No predictions available.")
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
                    for detection in detections {
                        let predictionResult = PredictionResultEntity(context: viewContext)
                        let scanner = Scanner(string: detection.frameName)
                        scanner.scanString("frame")
                        let frameIndex = scanner.scanInt() ?? 0
                        predictionResult.frameIndex = Int16(frameIndex)
                        predictionResult.video = videoEntity
                        if let detectedObject = detection.detection {
                            predictionResult.x = detectedObject.minX
                            predictionResult.y = detectedObject.minY
                            predictionResult.width = detectedObject.width
                            predictionResult.height = detectedObject.height
                        } else {
                            print("No tectected object")
                            predictionResult.x = 0.0
                            predictionResult.y = 0.0
                            predictionResult.width = 0.0
                            predictionResult.height = 0.0
                        }
                        do {
                            try viewContext.save()
                        } catch {
                            let nsError = error as NSError
                            print("Error saving detections: \(nsError), \(nsError.userInfo)")
                        }
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

    private func addDetection(_ frame: String, _ detectionResult: VNRecognizedObjectObservation) {
        let boundingBox = detectionResult.boundingBox
        let newBoundingBox = CGRect(
            x: boundingBox.origin.y, y: boundingBox.origin.x,
            width: boundingBox.height, height: boundingBox.width)
        detections.append((frame, newBoundingBox))
    }

    private func overlayVideo(_ videoEntity: VideoEntity) async {
        await MainActor.run {
            isExporting = true
        }
        
        let detectionFrames = videoEntity.predictions
        
        if let detectionsNSSet = detectionFrames,
           let detections = detectionsNSSet.allObjects as? [PredictionResultEntity] {
            let detections = detections.map({$0.toDetectionFrame()})
            let sortedDetectionFrames = detections.sorted(by: { $0.frameName < $1.frameName })
            print("Sorted frames count: \(sortedDetectionFrames.count)")
//            let sortedDetectionFrames: [DetectionFrame] = []
            guard
                let documentsDirectory = FileManager.default.urls(
                    for: .documentDirectory, in: .userDomainMask
                ).first
            else {
                print("Error: Couldn't find documents directory")
                return
            }

            let outputURL = documentsDirectory.appendingPathComponent("outputVideo.mp4")
            print("Output directory: \(outputURL.path)")
            print("Starting video processing...")
            
            if let videoURL = videoEntity.videoUrl {
                do {
                    let resultURL = try await overlayDetectionsOnVideo(
                        inputURL: videoURL, detectionFrames: sortedDetectionFrames,
                        outputURL: outputURL)
                    print("Video processing completed successfully")
                    print("Output video saved at: \(resultURL.path)")
                    await MainActor.run {
                        isExporting = false
                    }
                    
                } catch {
                    await MainActor.run {
                        isExporting = false
                    }
                    
                    print("Error processing video: \(error.localizedDescription)")
                }
            } else {
                print("Missing url")
                return
            }
        } else {
            print("There are no detections")
            return
        }
    }
}

#Preview {
    let context = PersistenceController.preview.container.viewContext
    let fetchRequest: NSFetchRequest<VideoEntity> = VideoEntity.fetchRequest()
    let videos = try? context.fetch(fetchRequest)
    let exampleVideo = videos?.first  // Get the first video (our example)

    VideoDetailView(videoEntity: exampleVideo!)
        .environment(\.managedObjectContext, context)
}
