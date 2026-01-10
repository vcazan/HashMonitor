//
//  SettingsView.swift
//  HashRipper-iOS
//
//  App settings
//

import SwiftUI
import HashRipperKit

struct SettingsView: View {
    @AppStorage("refreshInterval") private var refreshInterval = 30
    @AppStorage("showOfflineMiners") private var showOfflineMiners = true
    
    var body: some View {
        Form {
            Section("Refresh") {
                Picker("Auto-refresh interval", selection: $refreshInterval) {
                    Text("15 seconds").tag(15)
                    Text("30 seconds").tag(30)
                    Text("1 minute").tag(60)
                    Text("5 minutes").tag(300)
                    Text("Manual only").tag(0)
                }
            }
            
            Section("Display") {
                Toggle("Show offline miners", isOn: $showOfflineMiners)
            }
            
            Section("About") {
                HStack {
                    Text("Version")
                    Spacer()
                    Text("1.0.0")
                        .foregroundStyle(.secondary)
                }
                
                Link(destination: URL(string: "https://github.com/bitaxeorg")!) {
                    HStack {
                        Text("Bitaxe Project")
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Settings")
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}

