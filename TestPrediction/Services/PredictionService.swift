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
    private(set) var detectedObject: VNRecognizedObjectObservation?
    private(set) var processedImage: UIImage?
    
    func detectObjects(in image: CGImage) throws -> VNRecognizedObjectObservation? {
        guard let modelURL = Bundle.main.url(forResource: "WeightPlate1", withExtension: "mlmodelc") else {
            throw NSError(domain: "", code: 0, userInfo: nil)
        }
        
        do {
            let visionModel = try VNCoreMLModel(for: MLModel(contentsOf: modelURL))
            let request = createVisionRequest(with: visionModel)
            
            let handler = VNImageRequestHandler(cgImage: image)
            try handler.perform([request])
            
            return detectedObject
        } catch {
            debugInfo += "\nFailed to perform detection: \(error.localizedDescription)"
            return nil
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
        detectedObject = results.first
        
//        compactMap { observation in
//        guard let label = observation.labels.first else { return nil }
//        return observation
//    }
        
//        debugInfo += "\nDetected objects: \(detectedObjects.joined(separator: ", "))"
        
        if !results.isEmpty {
            //drawBoundingBoxes(results: results)
        }
    }
    
    func drawBoundingBoxes(result: VNRecognizedObjectObservation, cgImage: CGImage) -> UIImage {
        //guard let image = processedImage else { return }
        let image = UIImage(cgImage: cgImage, scale: 1.0, orientation: .right)
        
        UIGraphicsBeginImageContextWithOptions(image.size, false, 0.0)
        image.draw(in: CGRect(origin: .zero, size: image.size))
        
        let context = UIGraphicsGetCurrentContext()!
        context.setLineWidth(4)
        context.setStrokeColor(UIColor.green.cgColor)
        
//        for (index, observation) in results.enumerated() {
//            var boundingBox = observation.boundingBox
//            boundingBox.origin.y = 1 - boundingBox.origin.y - boundingBox.height
//            
//            let rect = VNImageRectForNormalizedRect(boundingBox, Int(image.size.width), Int(image.size.height))
//            context.stroke(rect)
//            
//            debugInfo += "\nBounding box \(index): \(rect)"
//        }
        
        let boundingBox = result.boundingBox
        let newBoundingBox = CGRect(x: boundingBox.origin.y, y: boundingBox.origin.x, width: boundingBox.height, height: boundingBox.width)
        //boundingBox.origin.y = 1 - boundingBox.origin.y - boundingBox.height
        
        let rect = VNImageRectForNormalizedRect(newBoundingBox, Int(image.size.width), Int(image.size.height))
        context.stroke(rect)
        
        processedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return processedImage ?? image
    }
}
