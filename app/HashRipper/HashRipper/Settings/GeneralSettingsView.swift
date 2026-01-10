//
//  GeneralSettingsView.swift
//  HashRipper
//
//  Created by Matt Sellars
//

import SwiftUI

struct GeneralSettingsView: View {
    @Environment(\.minerClientManager) private var minerClientManager
    @EnvironmentObject private var statusBarManager: StatusBarManager
    @State private var settings = AppSettings.shared
    @State private var appearanceMode: AppSettings.AppearanceMode = .system
    @State private var minerRefreshInterval: Double = 10.0
    @State private var backgroundPollingInterval: Double = 30.0
    @State private var focusedMinerRefreshInterval: Double = 5.0
    @State private var isStatusBarEnabled: Bool = true
    @State private var showDockBadge: Bool = {
        // Default to true if never set
        if UserDefaults.standard.object(forKey: "showDockBadge") == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: "showDockBadge")
    }()
    @State private var offlineThreshold: Int = 5
    @State private var usePersistentDeployments: Bool = false
    @State private var websocketLogBufferSize: Int = 1000
    
    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    // Appearance selector at the top
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Appearance")
                            .font(.headline)
                        
                        HStack(spacing: 12) {
                            ForEach(AppSettings.AppearanceMode.allCases, id: \.rawValue) { mode in
                                AppearanceButton(
                                    mode: mode,
                                    isSelected: appearanceMode == mode
                                ) {
                                    appearanceMode = mode
                                    settings.appearanceMode = mode
                                }
                            }
                        }
                        
                        Text("Choose how HashWatcher appears on your Mac.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Miner Refresh Interval")
                                .font(.headline)
                            Spacer()
                            Text("\(Int(minerRefreshInterval)) seconds")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                        
                        Slider(
                            value: $minerRefreshInterval,
                            in: 5...60,
                            step: 5
                        ) {
                            Text("Refresh Interval")
                        } minimumValueLabel: {
                            Text("5s")
                                .font(.caption)
                        } maximumValueLabel: {
                            Text("60s")
                                .font(.caption)
                        }
                        .onChange(of: minerRefreshInterval) { _, newValue in
                            settings.minerRefreshInterval = newValue
                            minerClientManager?.refreshIntervalSettingsChanged()
                        }
                        
                        Text("How often to refresh miner statistics and status information.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Focused Miner Refresh")
                                .font(.headline)
                            Spacer()
                            Text("\(Int(focusedMinerRefreshInterval)) seconds")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                        
                        Slider(
                            value: $focusedMinerRefreshInterval,
                            in: 2...15,
                            step: 1
                        ) {
                            Text("Focused Refresh Interval")
                        } minimumValueLabel: {
                            Text("2s")
                                .font(.caption)
                        } maximumValueLabel: {
                            Text("15s")
                                .font(.caption)
                        }
                        .onChange(of: focusedMinerRefreshInterval) { _, newValue in
                            settings.focusedMinerRefreshInterval = newValue
                        }
                        
                        Text("How often to refresh when viewing a specific miner's details. Faster for real-time monitoring.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Background Polling Interval")
                                .font(.headline)
                            Spacer()
                            Text("\(Int(backgroundPollingInterval)) seconds")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                        
                        Slider(
                            value: $backgroundPollingInterval,
                            in: 15...120,
                            step: 15
                        ) {
                            Text("Background Polling Interval")
                        } minimumValueLabel: {
                            Text("15s")
                                .font(.caption)
                        } maximumValueLabel: {
                            Text("120s")
                                .font(.caption)
                        }
                        .onChange(of: backgroundPollingInterval) { _, newValue in
                            settings.backgroundPollingInterval = newValue
                            minerClientManager?.refreshIntervalSettingsChanged()
                        }
                        
                        Text("How often to poll miners when the app is in the background or minimized.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Show Status Bar")
                                .font(.headline)
                            Spacer()
                            Toggle("", isOn: $isStatusBarEnabled)
                                .onChange(of: isStatusBarEnabled) { _, newValue in
                                    settings.isStatusBarEnabled = newValue
                                }
                        }

                        Text("Show mining statistics in the macOS menu bar for quick access.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Divider()
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Show Hash Rate on Dock Icon")
                                .font(.headline)
                            Spacer()
                            Toggle("", isOn: $showDockBadge)
                                .onChange(of: showDockBadge) { _, newValue in
                                    statusBarManager.showDockBadge = newValue
                                }
                        }

                        Text("Display total hash rate as a badge on the app's dock icon.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Offline Threshold")
                                .font(.headline)
                            Spacer()
                            Text("\(offlineThreshold) consecutive timeouts")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }

                        Slider(
                            value: Binding(
                                get: { Double(offlineThreshold) },
                                set: { offlineThreshold = Int($0) }
                            ),
                            in: 3...20,
                            step: 1
                        ) {
                            Text("Offline Threshold")
                        } minimumValueLabel: {
                            Text("3")
                                .font(.caption)
                        } maximumValueLabel: {
                            Text("20")
                                .font(.caption)
                        }
                        .onChange(of: offlineThreshold) { _, newValue in
                            settings.offlineThreshold = newValue
                        }

                        Text("Number of consecutive timeout errors before a miner is marked as offline.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Websocket Log Buffer Size")
                                .font(.headline)
                            Spacer()
                            Text("\(websocketLogBufferSize) entries")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }

                        Slider(
                            value: Binding(
                                get: { Double(websocketLogBufferSize) },
                                set: { websocketLogBufferSize = Int($0) }
                            ),
                            in: 100...10000,
                            step: 100
                        ) {
                            Text("Websocket Log Buffer Size")
                        } minimumValueLabel: {
                            Text("100")
                                .font(.caption)
                        } maximumValueLabel: {
                            Text("10k")
                                .font(.caption)
                        }
                        .onChange(of: websocketLogBufferSize) { _, newValue in
                            settings.websocketLogBufferSize = newValue
                        }

                        Text("Maximum number of websocket log entries to keep in memory. Higher values allow viewing more history but use more memory.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Use New Deployment System (Beta)")
                                .font(.headline)
                            Spacer()
                            Toggle("", isOn: $usePersistentDeployments)
                                .onChange(of: usePersistentDeployments) { _, newValue in
                                    settings.usePersistentDeployments = newValue
                                }
                        }

                        Text("Enable the new persistent deployment system with background processing and deployment history. Deployments will continue even if you quit the app.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Performance Tips")
                            .font(.headline)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "lightbulb")
                                    .foregroundColor(.orange)
                                    .font(.caption)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Lower intervals provide more real-time data but use more network resources.")
                                        .font(.caption)
                                    Text("Higher intervals reduce network load but data may be less current.")
                                        .font(.caption)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.thinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding()
            }
        }
        .formStyle(.grouped)
        .onAppear {
            appearanceMode = settings.appearanceMode
            minerRefreshInterval = settings.minerRefreshInterval
            backgroundPollingInterval = settings.backgroundPollingInterval
            focusedMinerRefreshInterval = settings.focusedMinerRefreshInterval
            isStatusBarEnabled = settings.isStatusBarEnabled
            showDockBadge = statusBarManager.showDockBadge
            offlineThreshold = settings.offlineThreshold
            usePersistentDeployments = settings.usePersistentDeployments
            websocketLogBufferSize = settings.websocketLogBufferSize
        }
    }
}

// MARK: - Appearance Button

private struct AppearanceButton: View {
    let mode: AppSettings.AppearanceMode
    let isSelected: Bool
    let action: () -> Void
    
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(previewBackground)
                        .frame(width: 60, height: 40)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(isSelected ? Color.blue : Color(nsColor: .separatorColor), lineWidth: isSelected ? 2 : 1)
                        )
                    
                    Image(systemName: mode.iconName)
                        .font(.system(size: 16))
                        .foregroundStyle(previewForeground)
                }
                
                Text(mode.displayName)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
    }
    
    private var previewBackground: Color {
        switch mode {
        case .system:
            return Color(nsColor: .controlBackgroundColor)
        case .light:
            return Color.white
        case .dark:
            return Color(white: 0.15)
        }
    }
    
    private var previewForeground: Color {
        switch mode {
        case .system:
            return .secondary
        case .light:
            return .black.opacity(0.7)
        case .dark:
            return .white.opacity(0.8)
        }
    }
}
