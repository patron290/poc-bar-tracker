import AVKit
import PhotosUI
import SwiftUI
import CoreData

struct VideoPickerView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var viewModel = VideoPickerViewModel()
    @State private var videoURL: URL?
    
    @FetchRequest(
        entity: VideoEntity.entity(),
        sortDescriptors: [NSSortDescriptor(keyPath: \VideoEntity.videoUrl, ascending: true)]
    )
    var videos: FetchedResults<VideoEntity>

    var body: some View {
        VStack {
            videoList
        }
        .onAppear {
            print(videos)
            viewModel.onPickVideo = { url in
                let video = VideoEntity(context: viewContext)
                video.videoName = url.lastPathComponent
                video.videoUrl = url
                do {
                    try viewContext.save()
                } catch {
                    print("Error saving video: \(error)")
                }
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
                ForEach(videos, id: \.objectID) { video in
                    if let videoName = video.videoName {
                        NavigationLink {
                            VideoDetailView(videoEntity: video)
                        } label: {
                            Text(videoName)
                        }
                    }
                }
            }
            .navigationTitle("Videos")
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
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
