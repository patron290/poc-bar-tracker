//
//  TestPredictionApp.swift
//  TestPrediction
//
//  Created by Balogh Patrik on 28/07/2024.
//

import SwiftUI

@main
struct TestPredictionApp: App {
    let presistenceController = PersistenceController.shared
    
    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(\.managedObjectContext, presistenceController.container.viewContext)
        }
    }
}
