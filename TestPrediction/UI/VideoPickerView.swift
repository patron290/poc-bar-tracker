import AVKit
import PhotosUI
import SwiftUI
import Vision

typealias DetectionFrame = (frameName: String, detection: CGRect?)

struct VideoPickerView: View {
    @StateObject private var viewModel = VideoPickerViewModel()
    @State private var isProcessing = false
    @State private var processingProgress: Double = 0.0
    @State private var extractor: VideoFrameExtractor?
    @State private var videoURL: URL?
    @State private var detections: [DetectionFrame] = []
    @State private var extractedFramesCount: Int = 0

    private var predictionService = PredictionService()

    var body: some View {
        VStack {
            Button("Select Video") {
                print("VideoProcessingView: Select Video button tapped")
                viewModel.pickVideo()
            }

            if isProcessing {
                ProgressView("Processing...")
                    .progressViewStyle(.circular)
                    .padding()
            }

            if let url = viewModel.videoURL {
                Text("\(url.lastPathComponent)")
            }
            
            if isProcessing {
                ProgressView(value: processingProgress, total: 1.0)
                    .progressViewStyle(LinearProgressViewStyle())
                    .padding()
                Text("\(Int(extractedFramesCount)) frames processed")

                Text("\(Int(processingProgress * 100))%")
                    .font(.headline)
            }

            if !isProcessing {
                Button(action: {
                    print("Click")
                    print(self.videoURL)
                    if let url = self.videoURL {
                        Task {
                            await self.overlayVideo(url, self.detections)
                        }
                    }
                }, label:{
                    Text("Text")
                })
                List(detections, id: \.frameName) { result in
                    Text("\(result.frameName) - \(String(describing: result.detection))")
                }
            }
        }
        .onAppear {
            viewModel.onPickVideo = { url in
                self.videoURL = url
                Task {
                    await self.processVideo(url: url)
                    //await self.overlayVideo(url, detections)
                }
            }
        }
    }
    
    private let extractionCompleted = Notification.Name("extractionCompleted")
    
    private func processVideo(url: URL) async {
        await MainActor.run {
            self.isProcessing = true
            self.processingProgress = 0.0
        }

        do {
            let extractor = try await VideoFrameExtractor(videoURL: url)
            self.extractor = extractor
            
            try await extractor.extractFrames { progress, extractedFrame, frameIndex in
                DispatchQueue.main.async {
                    self.processingProgress = progress
                    self.extractedFramesCount = frameIndex
                }
                
                let frameName = String(format: "frame%04d", frameIndex)
                
                if let frame = extractedFrame {
                    do {
                        let result = try self.predictionService.detectObjects(in: frame)
                        if let detectionResult = result {
                            addDetection(frameName, detectionResult)
                        }
                    } catch {
                        print("Error processing frame: \(error.localizedDescription)")
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
    
    private func overlayVideo(_ video: URL, _ detectionFrames: [DetectionFrame]) async {
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            print("Error: Couldn't find documents directory")
            return
        }
        
        // Define the output file URL
        let outputURL = documentsDirectory.appendingPathComponent("outputVideo.mp4")
        print("Output directory: \(outputURL.path)")
        print("Starting video processing...")
        
        if FileManager.default.fileExists(atPath: outputURL.path) {
            do {
                try FileManager.default.removeItem(at: outputURL)
            } catch {
                print("Error removing output file: \(error.localizedDescription)")
            }
        }
        
        do {
            // Call the async function and await its result
            let resultURL = try await overlayDetectionsOnVideo(inputURL: video, detectionFrames: detectionFrames, outputURL: outputURL)
            print("Video processing completed successfully")
            print("Output video saved at: \(resultURL.path)")
        } catch {
            print("Error processing video: \(error.localizedDescription)")
        }
    }
    
    private func addDetection(_ frame: String, _ detectionResult : VNRecognizedObjectObservation) {
        let boundingBox = detectionResult.boundingBox
        let newBoundingBox = CGRect(x: boundingBox.origin.y, y: boundingBox.origin.x, width: boundingBox.height, height: boundingBox.width)
        detections.append((frame,newBoundingBox))
    }
}


class VideoPickerViewModel: ObservableObject {
    @Published var videoURL: URL?
    var onPickVideo: ((URL) -> Void)?

    func pickVideo() {
        var config = PHPickerConfiguration()
        config.filter = .videos
        config.selectionLimit = 1

        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self

        // You'll need to present this picker from your SwiftUI view
        if let windowScene = UIApplication.shared.connectedScenes.first
            as? UIWindowScene,
            let rootViewController = windowScene.windows.first?
                .rootViewController
        {
            rootViewController.present(picker, animated: true)
        }
    }
}

extension VideoPickerViewModel: PHPickerViewControllerDelegate {
    func picker(
        _ picker: PHPickerViewController,
        didFinishPicking results: [PHPickerResult]
    ) {
        picker.dismiss(animated: true)

        guard let provider = results.first?.itemProvider else { return }

        if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
            provider.loadFileRepresentation(
                forTypeIdentifier: UTType.movie.identifier
            ) { [weak self] url, error in
                guard let self = self else { return }

                if let error = error {
                    print("Error loading video: \(error.localizedDescription)")
                    return
                }

                guard let url = url else { return }

                let documentsDirectory = FileManager.default.urls(
                    for: .documentDirectory, in: .userDomainMask)[0]
                let uniqueFileName = "\(UUID().uuidString).mov"
                let destinationURL = documentsDirectory.appendingPathComponent(
                    uniqueFileName)

                do {
                    try FileManager.default.copyItem(
                        at: url, to: destinationURL)
                    DispatchQueue.main.async {
                        self.videoURL = destinationURL
                        self.onPickVideo?(destinationURL)
                    }
                } catch {
                    print("Error copying video: \(error.localizedDescription)")
                }
            }
        }
    }
}
