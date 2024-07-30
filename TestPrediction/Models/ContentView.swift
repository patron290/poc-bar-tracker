import SwiftUI
import PhotosUI
import Vision

struct ContentView: View {
    @State private var selectedImage: UIImage?
    @State private var processedImage: UIImage?
    @State private var isImagePickerPresented = false
    @State private var detectedObjects: [String] = []
    @State private var debugInfo: String = ""
    @State private var confidenceThreshold: Float = 0.5
    @State private var isFullscreen = false
    @Namespace private var animation
    
    var body: some View {
        VStack {
            if let image = processedImage ?? selectedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 300)
            } else {
                Text("No image selected")
                    .foregroundColor(.gray)
            }
            
            Button("Select Image") {
                isImagePickerPresented = true
            }
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(10)
            
            if selectedImage != nil {
                Button("Detect Objects") {
                    detectObjects()
                }
                .padding()
                .background(Color.green)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            
            List(detectedObjects, id: \.self) { object in
                Text(object)
            }
            
            Text(debugInfo)
                            .font(.footnote)
                            .padding()
        }
        .sheet(isPresented: $isImagePickerPresented) {
            ImagePicker(image: $selectedImage)
        }
    }
    
    func detectObjects() {
        guard let image = selectedImage,
              let cgImage = image.cgImage else {
            debugInfo = "Failed to get CGImage from UIImage"
            return
        }
        
        debugInfo = "Image size: \(image.size.width) x \(image.size.height)"
        
        guard let modelURL = Bundle.main.url(forResource: "WeightPlate1", withExtension: "mlmodelc") else {
            print("Model not found.")
            debugInfo += "\nNo results from Vision request"
            return
        }
        
        do{
            let visionModel = try VNCoreMLModel(for: MLModel(contentsOf: modelURL))
            let request = VNCoreMLRequest(model: visionModel) { request, error in
                guard let results = request.results as? [VNRecognizedObjectObservation] else { return }
                
                self.detectedObjects = results.map { observation in
                    guard let label = observation.labels.first else { return "Unknown" }
                    return "\(label.identifier): \(Int(label.confidence * 100))%"
                }
                self.processResults(results)
            }
            
            // Set the input image size to match your model's expected input
            request.imageCropAndScaleOption = .scaleFill
            
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)
            do {
                try handler.perform([request])
                
            } catch {
                print("Failed to perform detection: \(error)")
                debugInfo += "\nFailed to perform detection: \(error)"
            }
        }
        catch {
            print("Failed to perform detection: \(error)")
            debugInfo += "\nFailed to perform detection: \(error)"
        }
    }
    
    func processResults(_ results: [Any]) {
        var detectedObjects: [String] = []
        var observations: [VNDetectedObjectObservation] = []
        
        for result in results {
            if let objectObservation = result as? VNRecognizedObjectObservation {
                if let label = objectObservation.labels.first {
                    detectedObjects.append("\(label.identifier): \(Int(label.confidence * 100))%")
                    debugInfo += "\nObject \(String(describing: index)): \(label.identifier) (\(label.confidence)%)"
                    debugInfo += "\nBounding box: \(objectObservation.boundingBox)"
                }
                observations.append(objectObservation)
            }
        }
        
        self.detectedObjects = detectedObjects
        
        if !observations.isEmpty {
            drawBoundingBoxes(results: observations)
        } else {
            self.processedImage = self.selectedImage
        }
    }
    
    
    func drawBoundingBoxes(results: [VNDetectedObjectObservation]) {
        guard let image = selectedImage else { return }
        
        debugInfo += "\nImage size for drawing: \(image.size.width) x \(image.size.height)"
        
        UIGraphicsBeginImageContextWithOptions(image.size, false, 0.0)
        image.draw(in: CGRect(origin: .zero, size: image.size))
        
        let context = UIGraphicsGetCurrentContext()!
        context.setLineWidth(8)
        context.setStrokeColor(UIColor.green.cgColor)
        
        for (index, observation) in results.enumerated() {
            var boundingBox = observation.boundingBox
            
            // Flip the Y coordinate for UIKit's coordinate system
            boundingBox.origin.y = 1 - boundingBox.origin.y - boundingBox.height
            
            let rect = VNImageRectForNormalizedRect(boundingBox, Int(image.size.width), Int(image.size.height))
            context.stroke(rect)
            
            debugInfo += "\nBounding box \(index): \(rect)"
        }
        
        let annotatedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        self.processedImage = annotatedImage
    }
}

struct ImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.presentationMode) private var presentationMode
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: ImagePicker
        
        init(_ parent: ImagePicker) {
            self.parent = parent
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.presentationMode.wrappedValue.dismiss()
            
            guard let provider = results.first?.itemProvider else { return }
            
            if provider.canLoadObject(ofClass: UIImage.self) {
                provider.loadObject(ofClass: UIImage.self) { image, _ in
                    DispatchQueue.main.async {
                        self.parent.image = image as? UIImage
                    }
                }
            }
        }
    }
}
