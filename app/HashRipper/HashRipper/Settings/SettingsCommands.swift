//
//  SettingsCommands.swift
//  HashRipper
//
//  Created by Matt Sellars
//

import SwiftUI

extension Notification.Name {
    static let switchToSettings = Notification.Name("switchToSettings")
}

struct SettingsCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About HashMonitor") {
                openWindow(id: AboutView.windowGroupId)
            }
        }

        CommandGroup(replacing: .appSettings) {
            Button("Settings…") {
                // Post notification to switch to Settings tab in main app
                NotificationCenter.default.post(name: .switchToSettings, object: nil)
                // Also bring main window to front
                NSApplication.shared.activate(ignoringOtherApps: true)
                if let mainWindow = NSApplication.shared.windows.first(where: { 
                    !$0.title.contains("About") && 
                    !$0.title.contains("Downloads") &&
                    !$0.title.contains("Deployments") &&
                    $0.canBecomeKey
                }) {
                    mainWindow.makeKeyAndOrderFront(nil)
                }
            }
            .keyboardShortcut(",", modifiers: .command)
        }
    }
}