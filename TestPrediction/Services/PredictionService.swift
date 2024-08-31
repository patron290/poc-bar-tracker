//
//  PredictionService.swift
//  TestPrediction
//
//  Created by Balogh Patrik on 2024. 08. 04..
//

import Foundation
import Vision
import PhotosUI

class PredictionService {
    private(set) var debugInfo: String = ""
    private(set) var detectedObjects: [String] = []
    private(set) var processedImage: UIImage?
    
    func detectObjects(in image: CGImage) throws -> [String] {
        guard let modelURL = Bundle.main.url(forResource: "WeightPlate1", withExtension: "mlmodelc") else {
            throw NSError(domain: "", code: 0, userInfo: nil)
        }
        
        do {
            let visionModel = try VNCoreMLModel(for: MLModel(contentsOf: modelURL))
            let request = createVisionRequest(with: visionModel)
            
            let handler = VNImageRequestHandler(cgImage: image, orientation: .up)
            try handler.perform([request])
            
            return detectedObjects
        } catch {
            debugInfo += "\nFailed to perform detection: \(error.localizedDescription)"
            return []
        }
    }
    
    private func createVisionRequest(with model: VNCoreMLModel) -> VNCoreMLRequest {
        let request = VNCoreMLRequest(model: model) { [weak self] request, error in
            guard let results = request.results as? [VNRecognizedObjectObservation] else { return }
            self?.processResults(results)
        }
        request.imageCropAndScaleOption = .scaleFill
        return request
    }
    
    private func processResults(_ results: [VNRecognizedObjectObservation]) {
        detectedObjects = results.compactMap { observation in
            guard let label = observation.labels.first else { return nil }
            return "\(label.identifier): \(Int(label.confidence * 100))%,\(observation.boundingBox)"
        }
        
        debugInfo += "\nDetected objects: \(detectedObjects.joined(separator: ", "))"
        
        if !results.isEmpty {
            drawBoundingBoxes(results: results)
        }
    }
    
    private func drawBoundingBoxes(results: [VNRecognizedObjectObservation]) {
        guard let image = processedImage else { return }
        
        UIGraphicsBeginImageContextWithOptions(image.size, false, 0.0)
        image.draw(in: CGRect(origin: .zero, size: image.size))
        
        let context = UIGraphicsGetCurrentContext()!
        context.setLineWidth(8)
        context.setStrokeColor(UIColor.green.cgColor)
        
        for (index, observation) in results.enumerated() {
            var boundingBox = observation.boundingBox
            boundingBox.origin.y = 1 - boundingBox.origin.y - boundingBox.height
            
            let rect = VNImageRectForNormalizedRect(boundingBox, Int(image.size.width), Int(image.size.height))
            context.stroke(rect)
            
            debugInfo += "\nBounding box \(index): \(rect)"
        }
        
        processedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
    }
}

//class PredictionService {
//    var debugInfo: String = ""
//    private var detectedObjects: [String] = []
//    private var selectedImage: UIImage?
//    //private var imageToProcess: CGImage?
//    private var processedImage: UIImage?
//    
//    //selectedImage: inout UIImage?
//    func detectObjects(imageToProcess: inout CGImage) -> [String] {
//        //self.selectedImage = selectedImage
//        
////        guard let image = self.selectedImage,
////              let cgImage = image.cgImage else {
////            debugInfo = "Failed to get CGImage from UIImage"
////            return
////        }
//        
//        //self.imageToProcess = imageToProcess
//        
//        debugInfo = "Image size: \(imageToProcess.width) x \(imageToProcess.height)"
//        
//        guard let modelURL = Bundle.main.url(forResource: "WeightPlate1", withExtension: "mlmodelc") else {
//            print("Model not found.")
//            debugInfo += "\nNo results from Vision request"
//            return []
//        }
//        var detectionResult: [String] = []
//        do{
//            let visionModel = try VNCoreMLModel(for: MLModel(contentsOf: modelURL))
//            let request = VNCoreMLRequest(model: visionModel) { request, error in
//                guard let results = request.results as? [VNRecognizedObjectObservation] else { return }
//                
//                self.detectedObjects = results.map { observation in
//                    guard let label = observation.labels.first else { return "Unknown" }
//                    return "\(label.identifier): \(Int(label.confidence * 100))%"
//                }
//                detectionResult = self.processResults(results)
//            }
//            
//            request.imageCropAndScaleOption = .scaleFill
//            
//            let handler = VNImageRequestHandler(cgImage: imageToProcess, orientation: .up)
//                DispatchQueue.global(qos: .userInitiated).async {
//                    do {
//                        try handler.perform([request])
//                    } catch let error as NSError {
//                        print("Failed to perform image request: \(error)")
//                        return
//                    }
//                }
//            
//            return detectionResult
//        }
//        catch {
//            print("Failed to perform detection: \(error)")
//            debugInfo += "\nFailed to perform detection: \(error)"
//            return []
//        }
//    }
//    
//    private func processResults(_ results: [Any]) -> [String] {
//        var detectedObjects: [String] = []
//        var observations: [VNDetectedObjectObservation] = []
//        
//        for result in results {
//            if let objectObservation = result as? VNRecognizedObjectObservation {
//                if let label = objectObservation.labels.first {
//                    detectedObjects.append("\(label.identifier): \(Int(label.confidence * 100))%")
//                    debugInfo += "\nObject \(String(describing: index)): \(label.identifier) (\(label.confidence)%)"
//                    debugInfo += "\nBounding box: \(objectObservation.boundingBox)"
//                }
//                observations.append(objectObservation)
//            }
//        }
//        
//        self.detectedObjects = detectedObjects
//        
//        if !observations.isEmpty {
//            drawBoundingBoxes(results: observations)
//            return detectedObjects
//        } else {
//            self.processedImage = self.selectedImage
//            return []
//        }
//    }
//    
//    func drawBoundingBoxes(results: [VNDetectedObjectObservation]) {
//        guard let image = self.selectedImage else { return }
//        
//        debugInfo += "\nImage size for drawing: \(image.size.width) x \(image.size.height)"
//        
//        UIGraphicsBeginImageContextWithOptions(image.size, false, 0.0)
//        image.draw(in: CGRect(origin: .zero, size: image.size))
//        
//        let context = UIGraphicsGetCurrentContext()!
//        context.setLineWidth(8)
//        context.setStrokeColor(UIColor.green.cgColor)
//        
//        for (index, observation) in results.enumerated() {
//            var boundingBox = observation.boundingBox
//            
//            boundingBox.origin.y = 1 - boundingBox.origin.y - boundingBox.height
//            
//            let rect = VNImageRectForNormalizedRect(boundingBox, Int(image.size.width), Int(image.size.height))
//            context.stroke(rect)
//            
//            debugInfo += "\nBounding box \(index): \(rect)"
//        }
//        
//        let annotatedImage = UIGraphicsGetImageFromCurrentImageContext()
//        UIGraphicsEndImageContext()
//        
//        self.selectedImage = annotatedImage
//    }
//}
