import SwiftUI
import PhotosUI
import AVKit

struct VideoPickerView: View {
    @State private var videoURL: URL?
    @State private var isShowingPicker = false
    
    var body: some View {
        VStack {
            Button("Select Video") {
                isShowingPicker = true
            }
            
            if let videoURL = videoURL {
                VideoPlayer(player: AVPlayer(url: videoURL))
                    .frame(height: 300)
            }
        }
        .sheet(isPresented: $isShowingPicker) {
            VideoPicker(completion: { url in
                self.videoURL = url
            })
        }
    }
}

struct VideoPicker: UIViewControllerRepresentable {
    let completion: (URL) -> Void
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .videos
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: VideoPicker
        
        init(_ parent: VideoPicker) {
            self.parent = parent
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            
            guard let provider = results.first?.itemProvider else { return }
            
            if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
                provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, error in
                    if let error = error {
                        print("Error loading video: \(error.localizedDescription)")
                        return
                    }
                    
                    guard let url = url else { return }
                    
                    // Create a local copy of the video
                    let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    let uniqueFileName = "\(UUID().uuidString).mov"
                    let destinationURL = documentsDirectory.appendingPathComponent(uniqueFileName)
                    
                    do {
                        try FileManager.default.copyItem(at: url, to: destinationURL)
                        DispatchQueue.main.async {
                            self.parent.completion(destinationURL)
                        }
                    } catch {
                        print("Error copying video: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
}
