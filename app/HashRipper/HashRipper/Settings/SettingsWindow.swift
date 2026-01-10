//
//  SettingsWindow.swift
//  HashRipper
//
//  Created by Matt Sellars
//

import SwiftUI

struct SettingsWindow: View {
    static let windowGroupId = "settings-window"
    
    var body: some View {
        VStack {
            TabView {
                GeneralSettingsView()
                    .tabItem {
                        Label("General", systemImage: "gearshape")
                    }

                NetworkSettingsView()
                    .tabItem {
                        Label("Network", systemImage: "network")
                    }
            }
        }
        .frame(width: 600, height: 400)
        .navigationTitle("Settings")
    }
}
