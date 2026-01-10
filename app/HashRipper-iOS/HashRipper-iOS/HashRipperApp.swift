//
//  HashRipperApp.swift
//  HashRipper-iOS
//
//  iOS version of HashRipper for Bitcoin miner monitoring
//

import SwiftUI
import SwiftData
import HashRipperKit

@main
struct HashRipperApp: App {
    let modelContainer: ModelContainer
    
    init() {
        do {
            modelContainer = try createModelContainer()
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(modelContainer)
    }
}

