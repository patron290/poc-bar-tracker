//
//  HomeView.swift
//  TestPrediction
//
//  Created by Balogh Patrik on 2024. 11. 19..
//

import SwiftUI

struct HomeView: View {

    @State private var selection: String? = "video"

    var body: some View {
        TabView(selection: $selection) {
            VideoPickerView()
                .tabItem {
                    Label("Video", systemImage: "camera.on.rectangle.fill")
                }

            Text("Profile")
                .tabItem {
                    Label("Profile", systemImage: "person.circle")
                }
        }
    }
}

#Preview {
    HomeView()
}
