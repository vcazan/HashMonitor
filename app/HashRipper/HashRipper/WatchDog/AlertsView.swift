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
                        Text("\(actionLogs.count) total restart\(actionLogs.count == 1 ? "" : "s")")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    
                    if unreadCount > 0 {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(.blue)
                                .frame(width: 6, height: 6)
                            Text("\(unreadCount) new")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    // Show affected miners count
                    let affectedMiners = Set(actionLogs.map { $0.minerMacAddress }).count
                    if affectedMiners > 0 {
                        HStack(spacing: 6) {
                            Image(systemName: "cpu")
                                .foregroundStyle(.secondary)
                            Text("\(affectedMiners) miner\(affectedMiners == 1 ? "" : "s") affected")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    Text("Click to expand details")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    
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
                
                // Trigger Conditions
                SettingsCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Trigger Conditions")
                                    .font(.system(size: 14, weight: .semibold))
                                Text("Configure when WatchDog should restart a miner")
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
                            // Trigger Summary
                            triggerConditionSummary
                            
                            Divider()
                            
                            // Power Condition
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
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
                                }
                                
                                if settings.watchdogCheckPower {
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack {
                                            Text("Power threshold")
                                                .font(.system(size: 12))
                                                .foregroundStyle(.secondary)
                                            Spacer()
                                            Text("≤ \(settings.watchdogLowPowerThreshold, specifier: "%.1f") W")
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
                                        
                                        Text("Restart if power stays at or below this value")
                                            .font(.system(size: 10))
                                            .foregroundStyle(.tertiary)
                                    }
                                    .padding(.leading, 24)
                                }
                            }
                            
                            Divider()
                            
                            // Hash Rate Condition
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
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
                                }
                                
                                if settings.watchdogCheckHashRate {
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack {
                                            Text("Hash rate threshold")
                                                .font(.system(size: 12))
                                                .foregroundStyle(.secondary)
                                            Spacer()
                                            Text("< \(settings.watchdogHashRateThreshold, specifier: "%.1f") GH/s")
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
                                        
                                        Text("Restart if hash rate stays below this value")
                                            .font(.system(size: 10))
                                            .foregroundStyle(.tertiary)
                                    }
                                    .padding(.leading, 24)
                                }
                            }
                            
                            Divider()
                            
                            // Condition Logic
                            if settings.watchdogCheckPower && settings.watchdogCheckHashRate {
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
                                
                                Divider()
                            }
                            
                            // Consecutive Readings
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    HStack(spacing: 8) {
                                        Image(systemName: "number.circle.fill")
                                            .foregroundStyle(.purple)
                                            .frame(width: 16)
                                        Text("Consecutive Readings Required")
                                            .font(.system(size: 13, weight: .medium))
                                    }
                                    Spacer()
                                    Text("\(settings.watchdogConsecutiveUpdates)")
                                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
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
                                
                                Text("Number of consecutive checks that must fail before restarting")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.tertiary)
                            }
                            
                            Divider()
                            
                            // Timing Settings
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Timing")
                                    .font(.system(size: 13, weight: .medium))
                                
                                // Check Interval
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
                                
                                // Restart Cooldown
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text("Restart cooldown")
                                            .font(.system(size: 12))
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        Text(formatCooldown(settings.watchdogRestartCooldown))
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
                                    
                                    Text("Time to wait after a restart before allowing another")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            
                            Divider()
                            
                            // Reset to Defaults
                            HStack {
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
                                
                                Spacer()
                            }
                        }
                    }
                }
                
                // Current Configuration Summary
                if !settings.isWatchdogAdvancedModeEnabled {
                    SettingsCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Current Configuration")
                                .font(.system(size: 14, weight: .semibold))
                            
                            VStack(alignment: .leading, spacing: 8) {
                                InfoRow(icon: "bolt.fill", text: "Power threshold: ≤ \(String(format: "%.1f", settings.watchdogLowPowerThreshold))W")
                                InfoRow(icon: "cube.fill", text: "Hash rate threshold: < \(String(format: "%.1f", settings.watchdogHashRateThreshold)) GH/s")
                                InfoRow(icon: "number.circle.fill", text: "\(settings.watchdogConsecutiveUpdates) consecutive readings required")
                                InfoRow(icon: "timer", text: "\(formatCooldown(settings.watchdogRestartCooldown)) cooldown between restarts")
                            }
                            
                            Text("Enable advanced mode above to customize these settings")
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                                .padding(.top, 4)
                        }
                    }
                }
            }
            .padding(24)
        }
    }
    
    // MARK: - Trigger Summary View
    
    private var triggerConditionSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Restart will trigger when:")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            
            HStack(alignment: .top, spacing: 12) {
                // Visual condition builder
                VStack(alignment: .leading, spacing: 6) {
                    if settings.watchdogCheckPower && settings.watchdogCheckHashRate {
                        HStack(spacing: 6) {
                            conditionPill(icon: "bolt.fill", text: "Power ≤ \(String(format: "%.1f", settings.watchdogLowPowerThreshold))W", color: .orange)
                            
                            Text(settings.watchdogRequireBothConditions ? "AND" : "OR")
                                .font(.system(size: 10, weight: .bold))
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
                        Text("⚠️ No conditions enabled - WatchDog will not trigger restarts")
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
                            
                            Text("consecutive checks")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colorScheme == .dark ? Color(white: 0.08) : Color(white: 0.96))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
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
    @State private var isExpanded: Bool = false
    
    private var logDate: Date {
        Date(timeIntervalSince1970: Double(log.timestamp) / 1000.0)
    }
    
    /// Parse the reason string into structured components for display
    private var reasonComponents: [(icon: String, text: String)] {
        let parts = log.reason.components(separatedBy: " • ")
        return parts.compactMap { part in
            if part.contains("Power:") {
                return ("bolt.fill", part)
            } else if part.contains("Hash rate:") {
                return ("cube.fill", part)
            } else if part.contains("readings") {
                return ("number.circle.fill", part)
            } else {
                return ("info.circle.fill", part)
            }
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main row
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            }) {
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
                                .foregroundStyle(.primary)
                            
                            if !log.isRead {
                                Circle()
                                    .fill(.blue)
                                    .frame(width: 6, height: 6)
                            }
                        }
                        
                        Text("WatchDog restart triggered")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    // Time and expand indicator
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(logDate, format: .relative(presentation: .named))
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                        
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
            
            // Expanded details
            if isExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    // Reason breakdown
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Trigger Conditions")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        
                        ForEach(reasonComponents, id: \.text) { component in
                            HStack(spacing: 8) {
                                Image(systemName: component.icon)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.orange)
                                    .frame(width: 16)
                                
                                Text(component.text)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
                    
                    // Firmware info if available
                    if log.minerFirmwareVersion != nil || log.axeOSVersion != nil {
                        Divider()
                            .padding(.vertical, 4)
                        
                        HStack(spacing: 16) {
                            if let firmware = log.minerFirmwareVersion {
                                HStack(spacing: 4) {
                                    Text("Firmware:")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.tertiary)
                                    Text(firmware)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            
                            if let axeOS = log.axeOSVersion {
                                HStack(spacing: 4) {
                                    Text("AxeOS:")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.tertiary)
                                    Text(axeOS)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    
                    // Exact timestamp
                    HStack(spacing: 4) {
                        Text("Time:")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                        Text(logDate, format: .dateTime.month().day().hour().minute().second())
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.leading, 50) // Align with content
                .padding(.bottom, 12)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
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
