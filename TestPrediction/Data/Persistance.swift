//
//  Persistance.swift
//  TestPrediction
//
//  Created by Balogh Patrik on 2024. 12. 04..
//

import CoreData

struct PersistenceController {
    static let shared = PersistenceController()
    let container: NSPersistentContainer
    
    @MainActor
    static let preview: PersistenceController = {
        let result = PersistenceController(inMemory: true)
        let viewContext = result.container.viewContext
        
        let exampleVideo = VideoEntity(context: viewContext)
        exampleVideo.videoName = UUID().uuidString
        exampleVideo.videoUrl = URL(string: "https://www.youtube.com/watch?v=111111111111")
        
        let examplePredictionResult = PredictionResultEntity(context: viewContext)
        examplePredictionResult.x = 0.5
        examplePredictionResult.y = 0.5
        examplePredictionResult.video = exampleVideo
        examplePredictionResult.height = 100
        examplePredictionResult.width = 50
        examplePredictionResult.frameIndex = 1
        
        do {
            try viewContext.save()
        } catch {
            print("Error saving context \(error)")
        }
        
        return result
    }()
    
    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "Model")
        
        if inMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        }
        container.loadPersistentStores { _, error in
            if let error = error as NSError? {
                print("Unresolved error \(error), \(error.userInfo)")
            }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
    }
}
