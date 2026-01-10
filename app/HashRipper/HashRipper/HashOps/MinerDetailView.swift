//
//  MinerDetailView.swift
//  HashRipper
//
//  Clean, modern miner detail view
//

import SwiftUI
import SwiftData

struct MinerDetailView: View {
    @Environment(\.minerClientManager) var minerClientManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.newMinerScanner) var newMinerScanner
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.openWindow) private var openWindow
    
    let miner: Miner
    var showChartsInspector: Binding<Bool>?
    var showSettingsInspector: Binding<Bool>?
    
    // Global action closures (passed from MainContentView)
    var addNewMiner: (() -> Void)?
    var addMinerManually: (() -> Void)?
    var rolloutProfile: (() -> Void)?
    
    // Local state for when no binding is provided
    @State private var localShowChartsSheet: Bool = false
    
    @State private var mostRecentUpdate: MinerUpdate?
    @State private var debounceTask: Task<Void, Never>?
    @State private var showMinerSettings: Bool = false
    @State private var showRestartConfirmation: Bool = false
    @State private var showRestartSuccessAlert: Bool = false
    @State private var isRestarting: Bool = false
    @State private var isLogsDrawerExpanded: Bool = false
    @State private var unreadWatchdogCount: Int = 0
    
    private var cardBackground: Color {
        colorScheme == .dark 
            ? Color(white: 0.12)
            : Color.white
    }
    
    private var cardShadow: Color {
        colorScheme == .dark
            ? Color.black.opacity(0.3)
            : Color.black.opacity(0.06)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Header
                    headerSection
                        .padding(.bottom, 8)
                    
                    // Pool bar
                    if miner.isOffline {
                        // Offline state
                        offlineStateView
                            .padding(.horizontal, 24)
                            .padding(.bottom, 24)
                    } else {
                        if let update = mostRecentUpdate {
                            poolBar(update: update)
                                .padding(.horizontal, 24)
                                .padding(.bottom, 20)
                        }
                        
                        // Stats grid
                        statsGrid
                            .padding(.horizontal, 24)
                            .padding(.bottom, 24)
                        
                        // Detailed sections
                        VStack(alignment: .leading, spacing: 20) {
                            detailedStatsSection
                            systemInfoSection
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 24)
                    }
                }
            }
            
            // Logs drawer at bottom
            MinerLogsDrawerView(miner: miner, isExpanded: $isLogsDrawerExpanded)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            loadLatestUpdate()
            // Enable focused mode for faster refresh while viewing this miner
            minerClientManager?.setFocusedMiner(miner.ipAddress)
        }
        .onChange(of: miner.macAddress) { _, _ in 
            loadLatestUpdate()
            // Update focused miner when selection changes
            minerClientManager?.setFocusedMiner(miner.ipAddress)
        }
        .onReceive(NotificationCenter.default.publisher(for: .minerUpdateInserted)) { notification in
            if let macAddress = notification.userInfo?["macAddress"] as? String,
               macAddress == miner.macAddress {
                updateWithDebounce()
            }
        }
        .onDisappear { 
            debounceTask?.cancel()
            // Disable focused mode when leaving
            minerClientManager?.setFocusedMiner(nil)
        }
        .sheet(isPresented: $localShowChartsSheet) {
            MinerChartsSheet(miner: miner, onClose: { localShowChartsSheet = false })
        }
        .alert("Restart Miner?", isPresented: $showRestartConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Restart", role: .destructive) {
                restartMiner()
            }
        } message: {
            Text("Are you sure you want to restart \(miner.hostName)? The miner will be temporarily offline while it reboots.")
        }
        .alert("Miner Restarted", isPresented: $showRestartSuccessAlert) {
            Button("OK") { }
        } message: {
            Text("\(miner.hostName) has been restarted successfully.")
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                // Miner icon
                Image.icon(forMinerType: miner.minerType)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 40, height: 40)
                
                // Miner info
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(miner.hostName)
                            .font(.system(size: 15, weight: .semibold))
                        
                        statusBadge
                    }
                    
                    HStack(spacing: 10) {
                        Text(miner.minerDeviceDisplayName)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        
                        // IP link
                        Link(destination: URL(string: "http://\(miner.ipAddress)/")!) {
                            HStack(spacing: 2) {
                                Image(systemName: "globe")
                                    .font(.system(size: 9))
                                Text(miner.ipAddress)
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                            }
                            .foregroundStyle(.blue)
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                Spacer()
                
                // All actions in one row
                HStack(spacing: 4) {
                    // Pause/Resume
                    if minerClientManager?.isPaused == true {
                        IconButton(icon: "play.circle", size: 26, iconSize: 12, tooltip: "Resume updates", action: { minerClientManager?.resumeMinerUpdates() })
                    } else {
                        IconButton(icon: "pause.circle", size: 26, iconSize: 12, tooltip: "Pause updates", action: { minerClientManager?.pauseMinerUpdates() })
                    }
                    
                    // Refresh stats
                    IconButton(icon: "arrow.clockwise.circle", size: 26, iconSize: 12, tooltip: "Refresh now", action: { minerClientManager?.refreshClientInfo() })
                    
                    Divider()
                        .frame(height: 16)
                        .padding(.horizontal, 4)
                    
                    // Miner-specific actions
                    IconButton(icon: "chart.xyaxis.line", size: 26, iconSize: 12, tooltip: "Charts", action: {
                        // Close settings if open, then toggle charts
                        showSettingsInspector?.wrappedValue = false
                        if let binding = showChartsInspector {
                            binding.wrappedValue.toggle()
                        } else {
                            localShowChartsSheet = true
                        }
                    })
                    
                    IconButton(icon: "slider.horizontal.3", size: 26, iconSize: 12, tooltip: "Tuning", action: {
                        // Close charts if open, then toggle settings
                        showChartsInspector?.wrappedValue = false
                        showSettingsInspector?.wrappedValue.toggle()
                    })
                    
                    if isRestarting {
                        ProgressView()
                            .scaleEffect(0.5)
                            .frame(width: 26, height: 26)
                    } else {
                        IconButton(icon: "arrow.clockwise", size: 26, iconSize: 12, tooltip: "Restart", action: { showRestartConfirmation = true })
                            .disabled(miner.isOffline)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minHeight: 64)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(Divider(), alignment: .bottom)
        .task {
            await loadWatchdogCount()
        }
    }
    
    private func scanForNewMiners() {
        Task {
            await newMinerScanner?.rescanDevicesStreaming()
        }
    }
    
    private func openWatchDogWindow() {
        NotificationCenter.default.post(name: .showAlertsTab, object: nil)
    }
    
    private func loadWatchdogCount() async {
        let descriptor = FetchDescriptor<WatchDogActionLog>(
            predicate: #Predicate<WatchDogActionLog> { $0.isRead == false }
        )
        do {
            let count = try modelContext.fetchCount(descriptor)
            await MainActor.run {
                unreadWatchdogCount = count
            }
        } catch {
            // Ignore
        }
    }
    
    private var statusBadge: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(miner.isOffline ? Color.red : Color.green)
                .frame(width: 7, height: 7)
                .overlay(
                    Circle()
                        .stroke(miner.isOffline ? Color.red : Color.green, lineWidth: 2)
                        .scaleEffect(miner.isOffline ? 1.0 : 1.5)
                        .opacity(miner.isOffline ? 0 : 0)
                )
            Text(miner.isOffline ? "Offline" : "Online")
                .font(.system(size: 12, weight: .medium))
                .contentTransition(.interpolate)
        }
        .foregroundStyle(miner.isOffline ? .red : .green)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background((miner.isOffline ? Color.red : Color.green).opacity(0.1))
        .clipShape(Capsule())
        .animation(.easeInOut(duration: 0.3), value: miner.isOffline)
    }
    
    // MARK: - Offline State View
    
    @State private var isRetrying: Bool = false
    
    private var offlineStateView: some View {
        VStack(spacing: 16) {
            Spacer()
            
            // Simple icon
            Image(systemName: isRetrying ? "antenna.radiowaves.left.and.right" : "wifi.slash")
                .font(.system(size: 32, weight: .thin))
                .foregroundStyle(.secondary)
                .opacity(isRetrying ? 0.6 : 0.4)
            
            VStack(spacing: 4) {
                Text(isRetrying ? "Connecting" : "Offline")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                
                if !isRetrying, let lastUpdate = mostRecentUpdate {
                    let date = Date(timeIntervalSince1970: TimeInterval(lastUpdate.timestamp) / 1000)
                    let timeAgo = date.formatted(.relative(presentation: .named))
                    Text("Last seen \(timeAgo)")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
            }
            
            // Retry button - minimal style
            Button(action: retryConnection) {
                HStack(spacing: 4) {
                    if isRetrying {
                        ProgressView()
                            .scaleEffect(0.6)
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10, weight: .medium))
                    }
                    Text(isRetrying ? "Connecting..." : "Retry")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(isRetrying ? .secondary : .primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(colorScheme == .dark ? Color(white: 0.15) : Color(white: 0.92))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .disabled(isRetrying)
            
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }
    
    private func retryConnection() {
        // Don't reset error counter here - let success/failure handlers manage it
        // This prevents the miner from briefly appearing "online" before the attempt completes
        isRetrying = true
        
        Task {
            // Trigger a refresh for this specific miner
            if let client = minerClientManager?.client(forIpAddress: miner.ipAddress) {
                let result = await client.getSystemInfo()
                
                await MainActor.run {
                    isRetrying = false
                    
                    switch result {
                    case .success:
                        // Success! Reset the error counter so miner shows as online
                        miner.consecutiveTimeoutErrors = 0
                        // Trigger a full refresh to update the UI
                        minerClientManager?.refreshClientInfo()
                    case .failure:
                        // Failed - miner stays offline, no change to counter
                        // The UI will stay on the offline view
                        break
                    }
                }
            } else {
                await MainActor.run {
                    isRetrying = false
                }
            }
        }
    }
    
    // MARK: - Pool Bar
    
    private func poolBar(update: MinerUpdate) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "server.rack")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            
            VStack(alignment: .leading, spacing: 1) {
                Text("Mining Pool")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                
                let url = update.isUsingFallbackStratum ? update.fallbackStratumURL : update.stratumURL
                let port = update.isUsingFallbackStratum ? update.fallbackStratumPort : update.stratumPort
                Text("\(url):\(port, format: .number.grouping(.never))")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .lineLimit(1)
            }
            
            Spacer()
            
            if update.isUsingFallbackStratum {
                Text("FALLBACK")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.8).combined(with: .opacity),
                        removal: .opacity
                    ))
            }
        }
        .padding(14)
        .background(cardBackground)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: update.isUsingFallbackStratum)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: cardShadow, radius: 2, x: 0, y: 1)
    }
    
    // MARK: - Stats Grid
    
    private var statsGrid: some View {
        HStack(spacing: 0) {
            // Hash Rate - primary metric
            VStack(alignment: .leading, spacing: 4) {
                Text("HASH RATE")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .tracking(0.3)
                
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(formattedHashRate.0)
                        .font(.system(size: 32, weight: .semibold, design: .rounded))
                        .contentTransition(.numericText())
                    Text(formattedHashRate.1)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            statDivider
            
            // Power
            VStack(alignment: .leading, spacing: 4) {
                Text("POWER")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .tracking(0.3)
                
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(String(format: "%.0f", mostRecentUpdate?.power ?? 0))
                        .font(.system(size: 32, weight: .semibold, design: .rounded))
                        .contentTransition(.numericText())
                    Text("W")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            statDivider
            
            // Efficiency
            VStack(alignment: .leading, spacing: 4) {
                Text("EFFICIENCY")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .tracking(0.3)
                
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(formattedEfficiency)
                        .font(.system(size: 32, weight: .semibold, design: .rounded))
                        .contentTransition(.numericText())
                    Text("J/TH")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(24)
        .background(colorScheme == .dark ? Color(white: 0.06) : .white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(colorScheme == .dark ? Color(white: 0.12) : Color(white: 0.9), lineWidth: 1)
        )
    }
    
    private var statDivider: some View {
        Rectangle()
            .fill(colorScheme == .dark ? Color(white: 0.15) : Color(white: 0.88))
            .frame(width: 1, height: 40)
            .padding(.horizontal, 24)
    }
    
    private var formattedEfficiency: String {
        guard let update = mostRecentUpdate else { return "—" }
        let thPerSecond = update.hashRate / 1000.0
        guard thPerSecond > 0 else { return "—" }
        return String(format: "%.1f", update.power / thPerSecond)
    }
    
    private var formattedHashRate: (String, String) {
        let rate = mostRecentUpdate?.hashRate ?? 0
        let formatted = formatMinerHashRate(rawRateValue: rate)
        return (formatted.rateString, formatted.rateSuffix)
    }
    
    private func tempColor(_ temp: Double) -> Color {
        if temp >= 70 { return .red }
        if temp >= 55 { return .orange }
        return .green
    }
    
    // MARK: - Detailed Stats Section
    
    private var detailedStatsSection: some View {
        HStack(spacing: 0) {
            // Temperature
            secondaryStat(label: "Temp", value: String(format: "%.0f°", mostRecentUpdate?.temp ?? 0))
            
            // VR Temp
            secondaryStat(label: "VR Temp", value: mostRecentUpdate?.vrTemp.map { String(format: "%.0f°", $0) } ?? "—")
            
            // Fan
            secondaryStat(label: "Fan", value: "\(mostRecentUpdate?.fanrpm ?? 0) RPM")
            
            // Frequency
            secondaryStat(label: "Freq", value: String(format: "%.0f MHz", mostRecentUpdate?.frequency ?? 0))
            
            // Shares
            secondaryStat(label: "Shares", value: formatShares(mostRecentUpdate?.sharesAccepted ?? 0))
            
            // Best Diff
            secondaryStat(label: "Best Diff", value: mostRecentUpdate?.bestDiff ?? "—")
            
            // Session
            secondaryStat(label: "Session", value: mostRecentUpdate?.bestSessionDiff ?? "—")
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .background(colorScheme == .dark ? Color(white: 0.06) : .white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(colorScheme == .dark ? Color(white: 0.12) : Color(white: 0.9), lineWidth: 1)
        )
    }
    
    private func secondaryStat(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private func formatShares(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }
    
    // MARK: - System Info Section
    
    private var systemInfoSection: some View {
        HStack(spacing: 0) {
            secondaryStat(label: "Firmware", value: mostRecentUpdate?.minerFirmwareVersion ?? "—")
            secondaryStat(label: "AxeOS", value: mostRecentUpdate?.axeOSVersion ?? "—")
            secondaryStat(label: "Uptime", value: formattedUptime)
            secondaryStat(label: "MAC", value: miner.macAddress)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .background(colorScheme == .dark ? Color(white: 0.06) : .white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(colorScheme == .dark ? Color(white: 0.12) : Color(white: 0.9), lineWidth: 1)
        )
    }
    
    private var formattedUptime: String {
        let seconds = mostRecentUpdate?.uptimeSeconds ?? 0
        let days = seconds / 86400
        let hours = (seconds % 86400) / 3600
        let minutes = (seconds % 3600) / 60
        
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }
    
    // MARK: - Actions
    
    private func loadLatestUpdate() {
        Task { @MainActor in
            let macAddress = miner.macAddress
            var descriptor = FetchDescriptor<MinerUpdate>(
                predicate: #Predicate<MinerUpdate> { $0.macAddress == macAddress },
                sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
            )
            descriptor.fetchLimit = 1
            mostRecentUpdate = try? modelContext.fetch(descriptor).first
        }
    }
    
    private func updateWithDebounce() {
        debounceTask?.cancel()
        debounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            if !Task.isCancelled { loadLatestUpdate() }
        }
    }
    
    private func restartMiner() {
        guard let client = minerClientManager?.client(forIpAddress: miner.ipAddress) else { return }
        isRestarting = true
        
        Task {
            let result = await client.restartClient()
            await MainActor.run {
                isRestarting = false
                if case .success = result { showRestartSuccessAlert = true }
            }
        }
    }
}

// MARK: - Supporting Components

private struct IconButton: View {
    let icon: String
    var size: CGFloat = 28
    var iconSize: CGFloat = 13
    var tooltip: String? = nil
    let action: () -> Void
    
    @Environment(\.colorScheme) var colorScheme
    @State private var isHovered: Bool = false
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: iconSize, weight: .medium))
                .foregroundStyle(isHovered ? .primary : .secondary)
                .frame(width: size, height: size)
                .background(isHovered 
                    ? (colorScheme == .dark ? Color(white: 0.25) : Color(white: 0.88))
                    : (colorScheme == .dark ? Color(white: 0.18) : Color(white: 0.94)))
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .animation(.easeOut(duration: 0.15), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(tooltip ?? "")
    }
}

private struct StatCard: View {
    let label: String
    let value: String
    let unit: String
    let color: Color
    
    @Environment(\.colorScheme) var colorScheme
    @State private var isHighlighted: Bool = false
    @State private var previousValue: String = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(0.5)
            
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(color)
                    .contentTransition(.numericText(value: Double(value) ?? 0))
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: value)
                Text(unit)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            ZStack {
                colorScheme == .dark ? Color(white: 0.12) : .white
                
                // Subtle highlight glow on update
                RoundedRectangle(cornerRadius: 10)
                    .fill(color.opacity(isHighlighted ? 0.08 : 0))
                    .animation(.easeOut(duration: 0.6), value: isHighlighted)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: colorScheme == .dark ? .black.opacity(0.3) : .black.opacity(0.06), radius: 2, x: 0, y: 1)
        .onChange(of: value) { oldValue, newValue in
            if oldValue != newValue && !previousValue.isEmpty {
                withAnimation(.easeIn(duration: 0.1)) {
                    isHighlighted = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    withAnimation(.easeOut(duration: 0.5)) {
                        isHighlighted = false
                    }
                }
            }
            previousValue = newValue
        }
        .onAppear {
            previousValue = value
        }
    }
}

private struct DetailCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
            
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(colorScheme == .dark ? Color(white: 0.12) : .white)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: colorScheme == .dark ? .black.opacity(0.3) : .black.opacity(0.06), radius: 2, x: 0, y: 1)
    }
}

private struct DetailStat: View {
    let label: String
    let value: String
    let unit: String
    
    @State private var isHighlighted: Bool = false
    @State private var previousValue: String = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 16, weight: .semibold, design: .monospaced))
                    .foregroundStyle(isHighlighted ? .blue : .primary)
                    .contentTransition(.numericText(value: Double(value) ?? 0))
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: value)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onChange(of: value) { oldValue, newValue in
            if oldValue != newValue && !previousValue.isEmpty {
                withAnimation(.easeIn(duration: 0.1)) {
                    isHighlighted = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    withAnimation(.easeOut(duration: 0.4)) {
                        isHighlighted = false
                    }
                }
            }
            previousValue = newValue
        }
        .onAppear {
            previousValue = value
        }
    }
}

private struct InfoItem: View {
    let label: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct TemperatureBar: View {
    let value: Double
    let max: Double
    
    private var percentage: Double { min(value / max, 1.0) }
    private var color: Color {
        if value >= 70 { return .red }
        if value >= 55 { return .orange }
        return .green
    }
    
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(nsColor: .separatorColor))
                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                    .frame(width: geo.size.width * percentage)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8), value: percentage)
            }
        }
        .frame(height: 4)
        .animation(.easeInOut(duration: 0.4), value: color)
    }
}

private struct AnimatedShareCounter: View {
    let value: Int
    let label: String
    let color: Color
    var isAlert: Bool = false
    
    @State private var isHighlighted: Bool = false
    @State private var previousValue: Int = 0
    
    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
                .scaleEffect(isHighlighted ? 1.4 : 1.0)
                .animation(.spring(response: 0.25, dampingFraction: 0.5), value: isHighlighted)
            
            Text(verbatim: "\(value)")
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .foregroundStyle(isAlert ? color : .primary)
                .contentTransition(.numericText())
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: value)
            
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .onChange(of: value) { oldValue, newValue in
            if oldValue != newValue && previousValue > 0 {
                withAnimation(.easeIn(duration: 0.1)) {
                    isHighlighted = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    withAnimation(.easeOut(duration: 0.3)) {
                        isHighlighted = false
                    }
                }
            }
            previousValue = newValue
        }
        .onAppear {
            previousValue = value
        }
    }
}
