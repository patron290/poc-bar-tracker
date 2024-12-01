import AVKit
import PhotosUI
import SwiftUI

struct VideoPickerView: View {
    @StateObject private var viewModel = VideoPickerViewModel()
    @State private var videoURL: URL?
    @State private var alreadySavedVideos: [URL] = []

    var body: some View {
        VStack {

            if let url = viewModel.videoURL {
                Text("\(url.lastPathComponent)")
            }
            
            videoList
           
        }
        .onAppear {
            if alreadySavedVideos.isEmpty {
                alreadySavedVideos = fetchVideosFromDocumentFolder()
            }
            viewModel.onPickVideo = { url in
                alreadySavedVideos.append(url)
            }
        }
    }
    
    var videoList: some View {
        NavigationStack {
            List {
                HStack {
                    Spacer()
                    Button {
                        print("VideoProcessingView: Select Video button tapped")
                        viewModel.pickVideo()
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                }
                ForEach(alreadySavedVideos, id: \.self) { videoURL in
                    NavigationLink {
                        VideoDetailView(videoURL: videoURL)
                    } label: {
                        Text(videoURL.path())
                    }
                }
            }
            .navigationTitle("Videos")
        }
    }
      
    private func fetchVideosFromDocumentFolder() -> [URL] {
        let fileManager = FileManager.default
        guard let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else { return []
        }
        
        do {
            let fileURLs = try fileManager.contentsOfDirectory(at: documentsDirectory, includingPropertiesForKeys: nil)
            return fileURLs.filter { $0.pathExtension == "mov" || $0.pathExtension == ".mp4"}
        } catch {
            print(error.localizedDescription)
            return []
        }
        
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

#Preview {
    VideoPickerView()
}
