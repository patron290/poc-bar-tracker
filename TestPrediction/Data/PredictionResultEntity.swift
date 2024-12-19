//
//  VideoEntity.swift
//  TestPrediction
//
//  Created by Balogh Patrik on 2024. 12. 17..
//

import Foundation

extension PredictionResultEntity {
    func toDetectionFrame() -> DetectionFrame {
        let frameName = String(format: "frame%04d", self.frameIndex)
        
        let detection = CGRect(
            x: self.x, y: self.y, width: self.width, height: self.height
        )
        
        return (frameName: frameName, detection: detection)
            
    }
}
