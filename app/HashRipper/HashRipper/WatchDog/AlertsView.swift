//
//  AlertsView.swift
//  HashRipper
//
//  Integrated alerts view for the main app
//

import SwiftUI
import SwiftData

struct AlertsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    
    @Query(
        sort: [SortDescriptor<WatchDogActionLog>(\.timestamp, order: .reverse)]
    ) private var actionLogs: [WatchDogActionLog]
    
    @Query(sort: [SortDescriptor<Miner>(\.hostName)]) private var allMiners: [Miner]
    
    @State private var selectedSegment: AlertSegment = .activity
    @State private var settings = AppSettings.shared
    @StateObject private var poolCoordinator = PoolMonitoringCoordinator.shared
    
    enum AlertSegment: String, CaseIterable {
        case activity = "Activity"
        case poolAlerts = "Pool Alerts"
        case settings = "Settings"
    }
    
    private var unreadCount: Int {
        actionLogs.filter { !$0.isRead }.count
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Alerts")
                        .font(.system(size: 20, weight: .semibold))
                    
                    Text("WatchDog activity and pool monitoring")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // Segment picker
                Picker("", selection: $selectedSegment) {
                    ForEach(AlertSegment.allCases, id: \.self) { segment in
                        Text(segment.rawValue).tag(segment)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 280)
            }
            .padding(24)
            
            Divider()
            
            // Content
            switch selectedSegment {
            case .activity:
                activityContent
            case .poolAlerts:
                poolAlertsContent
            case .settings:
                settingsContent
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onDisappear {
            markAllAsRead()
        }
    }
    
    // MARK: - Activity Content
    
    @ViewBuilder
    private var activityContent: some View {
        if actionLogs.isEmpty {
            emptyActivityState
        } else {
            VStack(spacing: 0) {
                // Stats bar
                HStack(spacing: 24) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise.circle")
                            .foregroundStyle(.orange)
                        Text("\(actionLogs.count) total restarts")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    
                    if unreadCount > 0 {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(.blue)
                                .frame(width: 6, height: 6)
                            Text("\(unreadCount) unread")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    Button("Clear All") {
                        clearAll()
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(colorScheme == .dark ? Color(white: 0.05) : Color(white: 0.97))
                
                // List
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(actionLogs) { log in
                            AlertActivityRow(log: log, miner: minerFor(log))
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
    }
    
    private var emptyActivityState: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.shield")
                .font(.system(size: 48, weight: .thin))
                .foregroundStyle(.secondary)
            
            Text("No Activity")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.secondary)
            
            Text("WatchDog is monitoring your miners.\nRestart actions will appear here.")
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Pool Alerts Content
    
    @ViewBuilder
    private var poolAlertsContent: some View {
        if poolCoordinator.activeAlerts.isEmpty {
            emptyPoolAlertsState
        } else {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(poolCoordinator.activeAlerts) { alert in
                        PoolAlertCard(alert: alert) {
                            poolCoordinator.dismissAlert(alert, modelContext: modelContext)
                        }
                    }
                }
                .padding(24)
            }
        }
    }
    
    private var emptyPoolAlertsState: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 48, weight: .thin))
                .foregroundStyle(.green)
            
            Text("All Clear")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.secondary)
            
            Text("No pool alerts detected.\nMonitoring \(poolCoordinator.monitoredMinerCount) miners.")
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Settings Content
    
    private var settingsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // WatchDog Enable/Disable
                SettingsCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("WatchDog")
                                    .font(.system(size: 14, weight: .semibold))
                                Text("Automatically restart unresponsive miners")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                            
                            Toggle("", isOn: Binding(
                                get: { settings.isWatchdogGloballyEnabled },
                                set: { settings.isWatchdogGloballyEnabled = $0 }
                            ))
                            .toggleStyle(.switch)
                        }
                    }
                }
                
                // Notifications
                SettingsCard {
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
                
                // Monitored Miners
                if settings.isWatchdogGloballyEnabled {
                    SettingsCard {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Monitored Miners")
                                    .font(.system(size: 14, weight: .semibold))
                                
                                Spacer()
                                
                                HStack(spacing: 8) {
                                    Button("All") {
                                        settings.enableWatchdogForAllMiners(allMiners.map { $0.macAddress })
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    
                                    Button("None") {
                                        settings.disableWatchdogForAllMiners()
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }
                            
                            Text("Select which miners WatchDog should monitor")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                            
                            if allMiners.isEmpty {
                                Text("No miners found")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.tertiary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 20)
                            } else {
                                VStack(spacing: 6) {
                                    ForEach(allMiners, id: \.macAddress) { miner in
                                        MinerWatchDogRow(miner: miner, settings: settings)
                                    }
                                }
                            }
                        }
                    }
                }
                
                // Advanced Settings
                SettingsCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Advanced Settings")
                                    .font(.system(size: 14, weight: .semibold))
                                Text("Fine-tune WatchDog thresholds")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                            
                            Toggle("", isOn: Binding(
                                get: { settings.isWatchdogAdvancedModeEnabled },
                                set: { settings.isWatchdogAdvancedModeEnabled = $0 }
                            ))
                            .toggleStyle(.switch)
                        }
                        
                        if settings.isWatchdogAdvancedModeEnabled {
                            Divider()
                            
                            // Restart Cooldown
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("Restart Cooldown")
                                        .font(.system(size: 13))
                                    Spacer()
                                    Text("\(Int(settings.watchdogRestartCooldown))s")
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                                
                                Slider(
                                    value: Binding(
                                        get: { settings.watchdogRestartCooldown },
                                        set: { settings.watchdogRestartCooldown = $0 }
                                    ),
                                    in: 60...600,
                                    step: 30
                                )
                                
                                Text("Time to wait between restart attempts")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.tertiary)
                            }
                            
                            Divider()
                            
                            // Check Interval
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("Check Interval")
                                        .font(.system(size: 13))
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
                                
                                Text("How often to check each miner's health")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.tertiary)
                            }
                            
                            Divider()
                            
                            // Low Power Threshold
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("Low Power Threshold")
                                        .font(.system(size: 13))
                                    Spacer()
                                    Text("\(settings.watchdogLowPowerThreshold, specifier: "%.1f")W")
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                                
                                Slider(
                                    value: Binding(
                                        get: { settings.watchdogLowPowerThreshold },
                                        set: { settings.watchdogLowPowerThreshold = $0 }
                                    ),
                                    in: 0.1...5.0,
                                    step: 0.1
                                )
                                
                                Text("Power below this triggers concern")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.tertiary)
                            }
                            
                            Divider()
                            
                            // Consecutive Updates
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("Consecutive Low Readings")
                                        .font(.system(size: 13))
                                    Spacer()
                                    Text("\(settings.watchdogConsecutiveUpdates)")
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                                
                                Slider(
                                    value: Binding(
                                        get: { Double(settings.watchdogConsecutiveUpdates) },
                                        set: { settings.watchdogConsecutiveUpdates = Int($0) }
                                    ),
                                    in: 2...10,
                                    step: 1
                                )
                                
                                Text("Number of low power readings before restart")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.tertiary)
                            }
                            
                            Divider()
                            
                            // Reset to Defaults
                            Button("Reset to Defaults") {
                                settings.watchdogRestartCooldown = 180
                                settings.watchdogCheckInterval = 30
                                settings.watchdogLowPowerThreshold = 0.1
                                settings.watchdogConsecutiveUpdates = 3
                            }
                            .font(.system(size: 12))
                            .foregroundStyle(.blue)
                        }
                    }
                }
                
                // How it works
                SettingsCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("How WatchDog Works")
                            .font(.system(size: 14, weight: .semibold))
                        
                        VStack(alignment: .leading, spacing: 8) {
                            InfoRow(icon: "eye", text: "Monitors power and hash rate for signs of failure")
                            InfoRow(icon: "timer", text: "Waits \(Int(settings.watchdogRestartCooldown / 60)) min between restart attempts")
                            InfoRow(icon: "power", text: "Issues restart after \(settings.watchdogConsecutiveUpdates) low readings")
                        }
                    }
                }
            }
            .padding(24)
        }
    }
    
    // MARK: - Helpers
    
    private func minerFor(_ log: WatchDogActionLog) -> Miner? {
        allMiners.first { $0.macAddress == log.minerMacAddress }
    }
    
    private func clearAll() {
        do {
            try modelContext.delete(model: WatchDogActionLog.self)
            try modelContext.save()
        } catch {
            print("Failed to clear alerts: \(error)")
        }
    }
    
    private func markAllAsRead() {
        let unread = actionLogs.filter { !$0.isRead }
        for log in unread {
            log.isRead = true
        }
        try? modelContext.save()
    }
}

// MARK: - Activity Row

private struct AlertActivityRow: View {
    let log: WatchDogActionLog
    let miner: Miner?
    
    @Environment(\.colorScheme) private var colorScheme
    
    private var logDate: Date {
        Date(timeIntervalSince1970: Double(log.timestamp) / 1000.0)
    }
    
    var body: some View {
        HStack(spacing: 14) {
            // Icon
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.1))
                    .frame(width: 36, height: 36)
                
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.orange)
            }
            
            // Content
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(miner?.hostName ?? "Unknown Miner")
                        .font(.system(size: 13, weight: .medium))
                    
                    if !log.isRead {
                        Circle()
                            .fill(.blue)
                            .frame(width: 6, height: 6)
                    }
                }
                
                Text("Restarted automatically")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Time
            Text(logDate, format: .relative(presentation: .named))
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .background(log.isRead ? Color.clear : (colorScheme == .dark ? Color.blue.opacity(0.03) : Color.blue.opacity(0.02)))
    }
}

// MARK: - Pool Alert Card

private struct PoolAlertCard: View {
    let alert: PoolAlertEvent
    let onDismiss: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.1))
                    .frame(width: 40, height: 40)
                
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.red)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(alert.minerHostname)
                    .font(.system(size: 14, weight: .semibold))
                
                Text("Unapproved pool: \(alert.poolIdentifier)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                
                Text(alert.detectedAt, format: .relative(presentation: .named))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            
            Spacer()
            
            Button("Dismiss") {
                onDismiss()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(16)
        .background(colorScheme == .dark ? Color(white: 0.08) : .white)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.red.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Settings Helper Views

private struct SettingsCard<Content: View>: View {
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

private struct MinerWatchDogRow: View {
    let miner: Miner
    let settings: AppSettings
    
    @State private var isEnabled: Bool = false
    
    var body: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: $isEnabled)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .onChange(of: isEnabled) { _, newValue in
                    if newValue {
                        settings.enableWatchdog(for: miner.macAddress)
                    } else {
                        settings.disableWatchdog(for: miner.macAddress)
                    }
                }
            
            VStack(alignment: .leading, spacing: 1) {
                Text(miner.hostName)
                    .font(.system(size: 13, weight: .medium))
                
                Text(miner.ipAddress)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            if isEnabled {
                Image(systemName: "shield.checkered")
                    .font(.system(size: 12))
                    .foregroundStyle(.green)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .onAppear {
            isEnabled = settings.isWatchdogEnabled(for: miner.macAddress)
        }
    }
}

private struct InfoRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(.blue)
                .frame(width: 20)
            
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }
}
