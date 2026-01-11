//
//  WatchDogSettingsView.swift
//  HashRipper
//
//  Created by Matt Sellars
//

import SwiftUI
import SwiftData

struct WatchDogSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: [SortDescriptor<Miner>(\.hostName)]) private var allMiners: [Miner]
    @State private var settings = AppSettings.shared
    @State private var isGloballyEnabled: Bool = true
    @State private var isPoolCheckerEnabled: Bool = false
    @State private var isHowItWorksExpanded: Bool = false
    @State private var isTriggerConditionsExpanded: Bool = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Global Toggle Section
                SettingsSection {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle(isOn: $isGloballyEnabled) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Enable WatchDog")
                                    .font(.system(size: 14, weight: .semibold))
                                Text("Automatically restart miners that become unresponsive")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.switch)
                        .onChange(of: isGloballyEnabled) { _, newValue in
                            settings.isWatchdogGloballyEnabled = newValue
                        }
                    }
                }
                
                if isGloballyEnabled {
                    // Trigger Conditions Section
                    SettingsSection {
                        VStack(alignment: .leading, spacing: 12) {
                            Button(action: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    isTriggerConditionsExpanded.toggle()
                                }
                            }) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Trigger Conditions")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(.primary)
                                        Text("Configure when WatchDog should restart a miner")
                                            .font(.system(size: 12))
                                            .foregroundStyle(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    Image(systemName: isTriggerConditionsExpanded ? "chevron.up" : "chevron.down")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(.secondary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            
                            // Always show summary
                            triggerConditionSummary
                            
                            if isTriggerConditionsExpanded {
                                Divider()
                                
                                triggerConditionsEditor
                            }
                        }
                    }
                    
                    // Monitored Miners Section
                    SettingsSection {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Monitored Miners")
                                    .font(.system(size: 14, weight: .semibold))
                                
                                Spacer()
                                
                                HStack(spacing: 8) {
                                    Button("All") { enableAllMiners() }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                    
                                    Button("None") { disableAllMiners() }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                }
                            }
                            
                            Text("Select which miners should be monitored")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                            
                            if allMiners.isEmpty {
                                HStack {
                                    Spacer()
                                    VStack(spacing: 8) {
                                        Image(systemName: "cpu")
                                            .font(.system(size: 24))
                                            .foregroundStyle(.tertiary)
                                        Text("No miners found")
                                            .font(.system(size: 12))
                                            .foregroundStyle(.tertiary)
                                    }
                                    .padding(.vertical, 20)
                                    Spacer()
                                }
                            } else {
                                VStack(spacing: 6) {
                                    ForEach(allMiners, id: \.macAddress) { miner in
                                        MinerWatchDogToggleRow(miner: miner, settings: settings)
                                    }
                                }
                            }
                        }
                    }
                    
                    // Notifications Section
                    SettingsSection {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Notifications")
                                .font(.system(size: 14, weight: .semibold))
                            
                            Toggle("Send system notifications", isOn: Binding(
                                get: { settings.areWatchdogNotificationsEnabled },
                                set: { settings.areWatchdogNotificationsEnabled = $0 }
                            ))
                            .font(.system(size: 13))
                            
                            if settings.areWatchdogNotificationsEnabled {
                                VStack(alignment: .leading, spacing: 8) {
                                    Toggle("When miner goes offline", isOn: Binding(
                                        get: { settings.notifyOnMinerOffline },
                                        set: { settings.notifyOnMinerOffline = $0 }
                                    ))
                                    .font(.system(size: 12))
                                    .padding(.leading, 20)
                                    
                                    Toggle("When WatchDog restarts a miner", isOn: Binding(
                                        get: { settings.notifyOnMinerRestart },
                                        set: { settings.notifyOnMinerRestart = $0 }
                                    ))
                                    .font(.system(size: 12))
                                    .padding(.leading, 20)
                                }
                            }
                        }
                    }
                    
                    // Pool Checker Section
                    SettingsSection {
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle(isOn: $isPoolCheckerEnabled) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Pool Checker")
                                        .font(.system(size: 14, weight: .semibold))
                                    Text("Verify miners are connected to approved pools")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .toggleStyle(.switch)
                            .onChange(of: isPoolCheckerEnabled) { _, newValue in
                                settings.isPoolCheckerEnabled = newValue
                            }
                            
                            if isPoolCheckerEnabled {
                                HStack(spacing: 6) {
                                    Image(systemName: "info.circle")
                                        .foregroundStyle(.blue)
                                    Text("Connects to miner websockets every 20 minutes to verify pool outputs.")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } else {
                    // Disabled state
                    SettingsSection {
                        VStack(spacing: 16) {
                            Image(systemName: "shield.slash")
                                .font(.system(size: 40, weight: .thin))
                                .foregroundStyle(.tertiary)
                            
                            Text("WatchDog is Disabled")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.secondary)
                            
                            Text("Enable WatchDog above to configure automatic miner monitoring and restarts.")
                                .font(.system(size: 12))
                                .foregroundStyle(.tertiary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 30)
                    }
                }
            }
            .padding(20)
        }
        .onAppear {
            isGloballyEnabled = settings.isWatchdogGloballyEnabled
            isPoolCheckerEnabled = settings.isPoolCheckerEnabled
        }
    }
    
    // MARK: - Trigger Condition Summary
    
    private var triggerConditionSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Restart will trigger when:")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
            
            VStack(alignment: .leading, spacing: 6) {
                if settings.watchdogCheckPower && settings.watchdogCheckHashRate {
                    HStack(spacing: 6) {
                        conditionPill(icon: "bolt.fill", text: "Power ≤ \(String(format: "%.1f", settings.watchdogLowPowerThreshold))W", color: .orange)
                        
                        Text(settings.watchdogRequireBothConditions ? "AND" : "OR")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        
                        conditionPill(icon: "cube.fill", text: "Hash < \(String(format: "%.0f", settings.watchdogHashRateThreshold)) GH/s", color: .blue)
                    }
                } else if settings.watchdogCheckPower {
                    conditionPill(icon: "bolt.fill", text: "Power ≤ \(String(format: "%.1f", settings.watchdogLowPowerThreshold))W", color: .orange)
                } else if settings.watchdogCheckHashRate {
                    conditionPill(icon: "cube.fill", text: "Hash < \(String(format: "%.0f", settings.watchdogHashRateThreshold)) GH/s", color: .blue)
                } else {
                    Text("⚠️ No conditions enabled")
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                }
                
                if settings.watchdogCheckPower || settings.watchdogCheckHashRate {
                    HStack(spacing: 4) {
                        Text("for")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        
                        Text("\(settings.watchdogConsecutiveUpdates)")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.purple)
                        
                        Text("consecutive checks, then wait")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        
                        Text(formatCooldown(settings.watchdogRestartCooldown))
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.green)
                        
                        Text("before next restart")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colorScheme == .dark ? Color(white: 0.08) : Color(white: 0.96))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    // MARK: - Trigger Conditions Editor
    
    private var triggerConditionsEditor: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Power Condition
            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: Binding(
                    get: { settings.watchdogCheckPower },
                    set: { settings.watchdogCheckPower = $0 }
                )) {
                    HStack(spacing: 8) {
                        Image(systemName: "bolt.fill")
                            .foregroundStyle(.orange)
                            .frame(width: 16)
                        Text("Low Power Detection")
                            .font(.system(size: 13, weight: .medium))
                    }
                }
                .toggleStyle(.switch)
                
                if settings.watchdogCheckPower {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Threshold")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("≤ \(String(format: "%.1f", settings.watchdogLowPowerThreshold)) W")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.orange)
                        }
                        
                        Slider(
                            value: Binding(
                                get: { settings.watchdogLowPowerThreshold },
                                set: { settings.watchdogLowPowerThreshold = $0 }
                            ),
                            in: 0.1...10.0,
                            step: 0.1
                        )
                    }
                    .padding(.leading, 24)
                }
            }
            
            Divider()
            
            // Hash Rate Condition
            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: Binding(
                    get: { settings.watchdogCheckHashRate },
                    set: { settings.watchdogCheckHashRate = $0 }
                )) {
                    HStack(spacing: 8) {
                        Image(systemName: "cube.fill")
                            .foregroundStyle(.blue)
                            .frame(width: 16)
                        Text("Low Hash Rate Detection")
                            .font(.system(size: 13, weight: .medium))
                    }
                }
                .toggleStyle(.switch)
                
                if settings.watchdogCheckHashRate {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Threshold")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("< \(String(format: "%.0f", settings.watchdogHashRateThreshold)) GH/s")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.blue)
                        }
                        
                        Slider(
                            value: Binding(
                                get: { settings.watchdogHashRateThreshold },
                                set: { settings.watchdogHashRateThreshold = $0 }
                            ),
                            in: 0.0...100.0,
                            step: 1.0
                        )
                    }
                    .padding(.leading, 24)
                }
            }
            
            // Condition Logic
            if settings.watchdogCheckPower && settings.watchdogCheckHashRate {
                Divider()
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Condition Logic")
                        .font(.system(size: 13, weight: .medium))
                    
                    Picker("", selection: Binding(
                        get: { settings.watchdogRequireBothConditions },
                        set: { settings.watchdogRequireBothConditions = $0 }
                    )) {
                        Text("Both conditions must be met (safer)").tag(true)
                        Text("Either condition triggers restart").tag(false)
                    }
                    .pickerStyle(.radioGroup)
                    .font(.system(size: 12))
                }
            }
            
            Divider()
            
            // Consecutive Readings
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: "number.circle.fill")
                            .foregroundStyle(.purple)
                            .frame(width: 16)
                        Text("Consecutive Readings")
                            .font(.system(size: 13, weight: .medium))
                    }
                    Spacer()
                    Text("\(settings.watchdogConsecutiveUpdates)")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.purple)
                }
                
                Slider(
                    value: Binding(
                        get: { Double(settings.watchdogConsecutiveUpdates) },
                        set: { settings.watchdogConsecutiveUpdates = Int($0) }
                    ),
                    in: 2...10,
                    step: 1
                )
                
                Text("Failed checks required before restarting")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            
            Divider()
            
            // Timing
            VStack(alignment: .leading, spacing: 12) {
                Text("Timing")
                    .font(.system(size: 13, weight: .medium))
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Check interval")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(settings.watchdogCheckInterval))s")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    
                    Slider(
                        value: Binding(
                            get: { settings.watchdogCheckInterval },
                            set: { settings.watchdogCheckInterval = $0 }
                        ),
                        in: 10...120,
                        step: 10
                    )
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Restart cooldown")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(formatCooldown(settings.watchdogRestartCooldown))
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.green)
                    }
                    
                    Slider(
                        value: Binding(
                            get: { settings.watchdogRestartCooldown },
                            set: { settings.watchdogRestartCooldown = $0 }
                        ),
                        in: 60...600,
                        step: 30
                    )
                    
                    Text("Time to wait after a restart before allowing another")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
            
            Divider()
            
            // Reset to Defaults
            Button("Reset to Defaults") {
                settings.watchdogRestartCooldown = 180
                settings.watchdogCheckInterval = 30
                settings.watchdogLowPowerThreshold = 0.1
                settings.watchdogHashRateThreshold = 1.0
                settings.watchdogConsecutiveUpdates = 3
                settings.watchdogRequireBothConditions = true
                settings.watchdogCheckPower = true
                settings.watchdogCheckHashRate = true
            }
            .font(.system(size: 12))
            .foregroundStyle(.blue)
        }
    }
    
    // MARK: - Helpers
    
    private func conditionPill(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
            Text(text)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
    
    private func formatCooldown(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        if secs == 0 {
            return "\(mins)m"
        } else {
            return "\(mins)m \(secs)s"
        }
    }
    
    private func enableAllMiners() {
        let macAddresses = allMiners.map { $0.macAddress }
        settings.enableWatchdogForAllMiners(macAddresses)
    }
    
    private func disableAllMiners() {
        settings.disableWatchdogForAllMiners()
    }
}

// MARK: - Settings Section Container

private struct SettingsSection<Content: View>: View {
    @ViewBuilder let content: Content
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(colorScheme == .dark ? Color(white: 0.1) : .white)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(colorScheme == .dark ? Color(white: 0.15) : Color(white: 0.9), lineWidth: 1)
            )
    }
}

struct MinerWatchDogToggleRow: View {
    let miner: Miner
    let settings: AppSettings
    
    @State private var isEnabled: Bool = false
    
    var body: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: $isEnabled)
                .labelsHidden()
                .onChange(of: isEnabled) { _, newValue in
                    if newValue {
                        settings.enableWatchdog(for: miner.macAddress)
                    } else {
                        settings.disableWatchdog(for: miner.macAddress)
                    }
                }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(miner.hostName)
                    .font(.callout)
                    .fontWeight(.medium)
                
                Text("\(miner.ipAddress) • \(miner.minerDeviceDisplayName)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if isEnabled {
                Image(systemName: "shield.checkered")
                    .foregroundColor(.green)
                    .font(.caption)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .onAppear {
            isEnabled = settings.isWatchdogEnabled(for: miner.macAddress)
        }
    }
}

struct WatchDogInfoRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .font(.callout)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout)
                    .fontWeight(.medium)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
