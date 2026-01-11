//
//  MinerDetailView.swift
//  HashMonitor
//
//  Apple Design Language - Health App inspired detail view
//

import SwiftUI
import SwiftData
import Charts
import HashRipperKit
import AxeOSClient

// MARK: - Main View

struct MinerDetailView: View {
    @Bindable var miner: Miner
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var latestUpdate: MinerUpdate?
    @State private var chartUpdates: [MinerUpdate] = []
    @State private var isRefreshing = false
    @State private var showSettings = false
    @State private var showLogs = false
    @State private var selectedTimeRange: TimeRange = .oneHour
    
    // Animation states
    @State private var headerAppeared = false
    @State private var statsAppeared = false
    @State private var chartAppeared = false
    
    private let session = URLSession.shared
    private let timer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()
    
    enum TimeRange: String, CaseIterable {
        case oneHour = "1H"
        case eightHours = "8H"
        case twentyFourHours = "24H"
        
        var seconds: TimeInterval {
            switch self {
            case .oneHour: return 3600
            case .eightHours: return 3600 * 8
            case .twentyFourHours: return 3600 * 24
            }
        }
    }
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: Spacing.xl) {
                // Hero Header
                heroHeader
                
                // Primary Stats Grid
                primaryStats
                
                // Performance Chart
                performanceChart
                
                // Mining Details
                miningDetails
                
                // Hardware Info
                hardwareInfo
                
                // Quick Actions
                quickActions
            }
            .padding(.vertical)
        }
        .background(AppColors.backgroundGrouped.ignoresSafeArea())
        .navigationTitle(miner.hostName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: Spacing.md) {
                    Button {
                        Haptics.impact(.light)
                        showLogs = true
                    } label: {
                        Image(systemName: "terminal")
                    }
                    
                    Button {
                        Haptics.impact(.light)
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
        }
        .refreshable {
            await refresh()
        }
        .onReceive(timer) { _ in
            Task { await refresh() }
        }
        .task {
            await initialLoad()
        }
        .sheet(isPresented: $showSettings) {
            MinerSettingsSheet(miner: miner)
        }
        .sheet(isPresented: $showLogs) {
            MinerLogsSheet(miner: miner)
        }
    }
    
    // MARK: - Hero Header
    
    private var heroHeader: some View {
        VStack(spacing: Spacing.lg) {
            // Miner Image & Status
            ZStack {
                // Glow effect
                if miner.isOnline {
                    Circle()
                        .fill(AppColors.statusOnline.opacity(0.15))
                        .frame(width: 100, height: 100)
                        .blur(radius: 20)
                }
                
                // Device image
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .fill(AppColors.backgroundGroupedSecondary)
                        .frame(width: 80, height: 80)
                    
                    Image(miner.minerType.imageName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                }
            }
            
            // Status badge
            StatusBadge(isOnline: miner.isOnline)
            
            // Primary metric - Hash Rate
            if let update = latestUpdate {
                VStack(spacing: Spacing.xxs) {
                    HStack(alignment: .lastTextBaseline, spacing: Spacing.xs) {
                        Text(formatHashRate(update.hashRate).value)
                            .font(.numericLarge)
                            .foregroundStyle(AppColors.textPrimary)
                            .contentTransition(.numericText())
                        
                        Text(formatHashRate(update.hashRate).unit)
                            .font(.titleMedium)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    
                    Text("Hash Rate")
                        .font(.captionLarge)
                        .foregroundStyle(AppColors.textTertiary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.xl)
        .opacity(headerAppeared ? 1 : 0)
        .offset(y: headerAppeared ? 0 : 20)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                headerAppeared = true
            }
        }
    }
    
    // MARK: - Primary Stats
    
    private var primaryStats: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Spacing.md) {
            if let update = latestUpdate {
                StatDisplay(
                    value: String(format: "%.1f", update.power),
                    unit: "W",
                    label: "Power",
                    icon: "bolt.fill",
                    color: AppColors.power
                )
                
                StatDisplay(
                    value: String(format: "%.0f", update.temp ?? 0),
                    unit: "°C",
                    label: "ASIC Temp",
                    icon: "thermometer.medium",
                    color: temperatureColor(update.temp ?? 0)
                )
                
                StatDisplay(
                    value: String(format: "%.0f", update.frequency ?? 0),
                    unit: "MHz",
                    label: "Frequency",
                    icon: "waveform",
                    color: AppColors.frequency
                )
                
                StatDisplay(
                    value: fanDisplayValue(update: update),
                    unit: update.autofanspeed == 1 ? "" : "%",
                    label: "Fan Speed",
                    icon: "fan.fill",
                    color: AppColors.efficiency
                )
            }
        }
        .padding(.horizontal)
        .opacity(statsAppeared ? 1 : 0)
        .offset(y: statsAppeared ? 0 : 20)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.1)) {
                statsAppeared = true
            }
        }
    }
    
    // MARK: - Performance Chart
    
    private var performanceChart: some View {
        VStack(spacing: Spacing.md) {
            // Header with time range picker
            HStack {
                Text("Performance")
                    .font(.titleSmall)
                    .foregroundStyle(AppColors.textPrimary)
                
                Spacer()
                
                // Time range pills
                HStack(spacing: Spacing.xs) {
                    ForEach(TimeRange.allCases, id: \.self) { range in
                        Button {
                            Haptics.selection()
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                selectedTimeRange = range
                            }
                            loadChartData()
                        } label: {
                            Text(range.rawValue)
                                .font(.captionLarge)
                                .fontWeight(selectedTimeRange == range ? .semibold : .medium)
                                .foregroundStyle(selectedTimeRange == range ? .white : AppColors.textSecondary)
                                .padding(.horizontal, Spacing.md)
                                .padding(.vertical, Spacing.sm)
                                .background(
                                    Capsule()
                                        .fill(selectedTimeRange == range ? Color.teal : AppColors.fillTertiary)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            
            // Chart
            if chartUpdates.count >= 2 {
                Chart {
                    ForEach(chartUpdates, id: \.timestamp) { update in
                        LineMark(
                            x: .value("Time", update.date),
                            y: .value("Hash Rate", update.hashRate)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(AppColors.chartLine.gradient)
                        
                        AreaMark(
                            x: .value("Time", update.date),
                            y: .value("Hash Rate", update.hashRate)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [AppColors.chartGradientTop, AppColors.chartGradientBottom],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisValueLabel(format: .dateTime.hour().minute())
                            .font(.captionSmall)
                            .foregroundStyle(AppColors.textTertiary)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                        AxisValueLabel {
                            if let val = value.as(Double.self) {
                                Text(String(format: "%.0f", val))
                                    .font(.captionSmall)
                                    .foregroundStyle(AppColors.textTertiary)
                            }
                        }
                    }
                }
                .frame(height: 180)
            } else {
                // Empty state for chart
                VStack(spacing: Spacing.md) {
                    ProgressView()
                        .tint(.teal)
                    
                    Text("Collecting data...")
                        .font(.captionLarge)
                        .foregroundStyle(AppColors.textTertiary)
                }
                .frame(height: 180)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(AppColors.backgroundGroupedSecondary)
        )
        .padding(.horizontal)
        .opacity(chartAppeared ? 1 : 0)
        .offset(y: chartAppeared ? 0 : 20)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.2)) {
                chartAppeared = true
            }
        }
    }
    
    // MARK: - Mining Details
    
    private var miningDetails: some View {
        VStack(spacing: Spacing.sm) {
            SectionHeader(title: "Mining")
                .padding(.horizontal)
            
            VStack(spacing: 1) {
                if let update = latestUpdate {
                    // Pool info
                    DetailRow(
                        icon: "network",
                        label: "Pool",
                        value: update.stratumURL
                    )
                    
                    DetailRow(
                        icon: "person.fill",
                        label: "Worker",
                        value: update.stratumUser
                    )
                    
                    DetailRow(
                        icon: "checkmark.circle.fill",
                        label: "Accepted",
                        value: "\(update.sharesAccepted ?? 0)"
                    )
                    
                    DetailRow(
                        icon: "xmark.circle.fill",
                        label: "Rejected",
                        value: "\(update.sharesRejected ?? 0)"
                    )
                    
                    DetailRow(
                        icon: "trophy.fill",
                        label: "Best Diff",
                        value: update.bestDiff ?? "—"
                    )
                    
                    DetailRow(
                        icon: "clock.fill",
                        label: "Uptime",
                        value: formatUptime(update.uptimeSeconds ?? 0)
                    )
                }
            }
            .appleCard(padding: 0)
            .padding(.horizontal)
        }
    }
    
    // MARK: - Hardware Info
    
    private var hardwareInfo: some View {
        VStack(spacing: Spacing.sm) {
            SectionHeader(title: "Hardware")
                .padding(.horizontal)
            
            VStack(spacing: 1) {
                DetailRow(
                    icon: "cpu",
                    label: "Model",
                    value: miner.minerDeviceDisplayName
                )
                
                if let update = latestUpdate {
                    DetailRow(
                        icon: "tag.fill",
                        label: "Firmware",
                        value: update.minerFirmwareVersion
                    )
                    
                    DetailRow(
                        icon: "bolt.circle.fill",
                        label: "Voltage",
                        value: String(format: "%.0f mV", update.voltage ?? 0)
                    )
                    
                    DetailRow(
                        icon: "thermometer.snowflake",
                        label: "VR Temp",
                        value: String(format: "%.0f °C", update.vrTemp ?? 0)
                    )
                }
                
                DetailRow(
                    icon: "wifi",
                    label: "IP Address",
                    value: miner.ipAddress
                )
            }
            .appleCard(padding: 0)
            .padding(.horizontal)
        }
    }
    
    // MARK: - Quick Actions
    
    private var quickActions: some View {
        VStack(spacing: Spacing.sm) {
            SectionHeader(title: "Actions")
                .padding(.horizontal)
            
            HStack(spacing: Spacing.md) {
                ActionButton(
                    icon: "arrow.clockwise",
                    label: "Restart",
                    color: .orange
                ) {
                    Task { await restartMiner() }
                }
                
                ActionButton(
                    icon: "safari",
                    label: "Web UI",
                    color: .blue
                ) {
                    openWebUI()
                }
            }
            .padding(.horizontal)
        }
        .padding(.bottom, Spacing.xxxl)
    }
    
    // MARK: - Helper Functions
    
    private func fanDisplayValue(update: MinerUpdate) -> String {
        if update.autofanspeed == 1 {
            return "Auto"
        }
        return String(format: "%.0f", update.fanspeed ?? 0)
    }
    
    private func formatHashRate(_ ghPerSec: Double) -> (value: String, unit: String) {
        if ghPerSec >= 1000 {
            return (String(format: "%.2f", ghPerSec / 1000), "TH/s")
        } else {
            return (String(format: "%.0f", ghPerSec), "GH/s")
        }
    }
    
    private func formatUptime(_ seconds: Int) -> String {
        let days = seconds / 86400
        let hours = (seconds % 86400) / 3600
        let minutes = (seconds % 3600) / 60
        
        if days > 0 {
            return "\(days)d \(hours)h"
        } else if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
    
    private func initialLoad() async {
        loadCachedData()
        await refresh()
    }
    
    private func loadCachedData() {
        latestUpdate = miner.getLatestUpdate(from: modelContext)
        loadChartData()
    }
    
    private func loadChartData() {
        let since = Date().addingTimeInterval(-selectedTimeRange.seconds)
        chartUpdates = miner.getUpdates(from: modelContext, since: since)
    }
    
    private func refresh() async {
        isRefreshing = true
        
        let client = AxeOSClient(deviceIpAddress: miner.ipAddress, urlSession: session)
        let result = await client.getSystemInfo()
        
        switch result {
        case .success(let info):
            await MainActor.run {
                miner.consecutiveTimeoutErrors = 0
                
                // Update hostname if changed
                if !info.hostname.isEmpty && miner.hostName != info.hostname {
                    miner.hostName = info.hostname
                }
                
                let update = MinerUpdate.from(miner: miner, info: info)
                modelContext.insert(update)
                
                latestUpdate = update
                loadChartData()
            }
        case .failure:
            await MainActor.run {
                miner.consecutiveTimeoutErrors += 1
            }
        }
        
        isRefreshing = false
    }
    
    private func restartMiner() async {
        let client = AxeOSClient(deviceIpAddress: miner.ipAddress, urlSession: session)
        let result = await client.restartClient()
        
        switch result {
        case .success:
            Haptics.notification(.success)
        case .failure:
            Haptics.notification(.error)
        }
    }
    
    private func openWebUI() {
        if let url = URL(string: "http://\(miner.ipAddress)") {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Detail Row

struct DetailRow: View {
    let icon: String
    let label: String
    let value: String
    
    var body: some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(AppColors.textTertiary)
                .frame(width: 24)
            
            Text(label)
                .font(.bodyMedium)
                .foregroundStyle(AppColors.textSecondary)
            
            Spacer()
            
            Text(value)
                .font(.bodyMedium)
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(1)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.md)
        .background(AppColors.backgroundGroupedSecondary)
    }
}

// MARK: - Action Button

struct ActionButton: View {
    let icon: String
    let label: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button {
            Haptics.impact(.medium)
            action()
        } label: {
            VStack(spacing: Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(color)
                
                Text(label)
                    .font(.captionLarge)
                    .foregroundStyle(AppColors.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.xl)
            .background(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(AppColors.backgroundGroupedSecondary)
            )
        }
        .buttonStyle(PressableStyle())
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        MinerDetailView(miner: Miner(
            hostName: "BitAxe-Ultra",
            ipAddress: "192.168.1.100",
            ASICModel: "BM1366",
            macAddress: "AA:BB:CC:DD:EE:FF"
        ))
    }
    .modelContainer(for: [Miner.self, MinerUpdate.self], inMemory: true)
}
