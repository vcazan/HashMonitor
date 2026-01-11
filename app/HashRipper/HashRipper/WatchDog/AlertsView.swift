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
                    
                    Text("WatchDog restarts and pool alerts")
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
                .frame(width: 220)
            }
            .padding(24)
            
            Divider()
            
            // Content
            switch selectedSegment {
            case .activity:
                activityContent
            case .poolAlerts:
                poolAlertsContent
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

