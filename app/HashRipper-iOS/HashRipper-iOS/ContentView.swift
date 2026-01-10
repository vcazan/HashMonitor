//
//  ContentView.swift
//  HashRipper-iOS
//
//  Main content view with tab-based navigation
//

import SwiftUI
import SwiftData
import HashRipperKit

struct ContentView: View {
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                MinerListView()
            }
            .tabItem {
                Label("Miners", systemImage: "cpu")
            }
            .tag(0)
            
            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
            .tag(1)
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(try! createModelContainer(inMemory: true))
}

