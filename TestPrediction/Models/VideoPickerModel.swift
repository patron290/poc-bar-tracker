//
//  File.swift
//  TestPrediction
//
//  Created by Balogh Patrik on 2024. 08. 14..
//

import Foundation
import PhotosUI

class VideoPickerModel: ObservableObject {
    @Published var selectedVideo: URL?
    
    func selectVideo() {
        var config = PHPickerConfiguration()
        config.filter = .videos
        config.selectionLimit = 1
        
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
    }
}

extension VideoPickerModel: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        
        guard let provider = results.first?.itemProvider else { return }
        
        if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
            provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { URL, error in
                if let error = error {
                    print("Error loading video: \(error.localizedDescription)")
                    return
                }
                
                guard let url = URL else { return }
                
                let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                let uniqueFilename = UUID().uuidString + ".mov"
                let destinationURL = documentsDirectory.appendingPathComponent(uniqueFilename)
                
                do {
                    try FileManager.default.copyItem(at: url, to: destinationURL)
                    DispatchQueue.main.async {
                        self.selectedVideo = destinationURL
                    }
                } catch {
                    print("Error copying video: \(error.localizedDescription)")
                }
            }
        }
    }
}
