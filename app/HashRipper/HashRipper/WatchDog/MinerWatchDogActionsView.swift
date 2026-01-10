//
//  MinerWatchDogActionsView.swift
//  HashRipper
//
//  Created by Matt Sellars
//

import SwiftUI
import SwiftData
import Charts

struct MinerWatchDogActionsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(
        sort: [SortDescriptor<WatchDogActionLog>(\.timestamp, order: .reverse)]
    ) private var actionLogs: [WatchDogActionLog]

    @Query private var allMiners: [Miner]

    @State private var markAsReadTask: Task<Void, Never>?
    @State private var unreadActionsWhenOpened: [WatchDogActionLog] = []
    @State private var selectedTab: WatchDogTab = .activity
    @StateObject private var poolCoordinator = PoolMonitoringCoordinator.shared

    static let windowGroupId = "miner-watchdog-actions"

    public init() {
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Tab Picker
                Picker("", selection: $selectedTab) {
                    Text("Activity")
                        .tag(WatchDogTab.activity)

                    Text("Pool Alerts")
                        .tag(WatchDogTab.poolAlerts)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Divider()

                // Tab Content
                if selectedTab == .activity {
                    activityTabContent
                } else {
                    PoolAlertsTab()
                }
            }
            .navigationTitle("Watch Dog Actions & Alerts")
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button("Refresh", systemImage: "arrow.clockwise") {
                        // SwiftData auto-updates, but this provides user feedback
                    }
                    .help("Refresh action history")
                }
            }
        }
        .frame(width: 800, height: 600)
        .onAppear {
            if selectedTab == .activity {
                startMarkAsReadTimer()
            }
        }
        .onDisappear {
            if selectedTab == .activity {
                markVisibleActionsAsRead()
            }
        }
    }

    @ViewBuilder
    private var activityTabContent: some View {
        VStack(spacing: 0) {
            if actionLogs.isEmpty {
                ContentUnavailableView(
                    "No Activity",
                    systemImage: "checkmark.shield",
                    description: Text("WatchDog is monitoring your miners. Actions will appear here.")
                )
            } else {
                // Summary header
                HStack(spacing: 16) {
                    Label("\(actionLogs.count) restarts", systemImage: "arrow.clockwise")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    
                    if let recent = actionLogs.first {
                        let date = Date(timeIntervalSince1970: Double(recent.timestamp) / 1000.0)
                        Label("Last: \(date, format: .relative(presentation: .named))", systemImage: "clock")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Button("Clear") {
                        clearAllActions()
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .controlSize(.small)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(NSColor.controlBackgroundColor))
                
                Divider()
                
                List {
                    ForEach(actionLogs) { actionLog in
                        WatchDogActionRowView(actionLog: actionLog, miners: allMiners)
                            .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    private func clearAllActions() {
        do {
            try modelContext.delete(model: WatchDogActionLog.self)
            try modelContext.save()
        } catch {
            print("Failed to clear WatchDog actions: \(error)")
        }
    }
    
    private func startMarkAsReadTimer() {
        // Capture unread actions that are currently visible
        unreadActionsWhenOpened = actionLogs.filter { !$0.isRead }
        
        // Cancel any existing timer
        markAsReadTask?.cancel()
        
        // Start a 10-second timer
        markAsReadTask = Task {
            try? await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
            
            if !Task.isCancelled {
                await markVisibleActionsAsRead()
            }
        }
    }
    
    private func markVisibleActionsAsRead() {
        markAsReadTask?.cancel()
        
        Task { @MainActor in
            // Mark the actions that were unread when window opened
            for action in unreadActionsWhenOpened where !action.isRead {
                action.isRead = true
            }
            
            do {
                try modelContext.save()
                print("Marked \(unreadActionsWhenOpened.count) WatchDog actions as read")
            } catch {
                print("Failed to mark WatchDog actions as read: \(error)")
            }
            
            unreadActionsWhenOpened.removeAll()
        }
    }
}

// Compact action row for the list
struct WatchDogActionRowView: View {
    let actionLog: WatchDogActionLog
    let miners: [Miner]
    
    private var miner: Miner? {
        miners.first { $0.macAddress == actionLog.minerMacAddress }
    }
    
    private var actionDate: Date {
        Date(timeIntervalSince1970: Double(actionLog.timestamp) / 1000.0)
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: "arrow.clockwise.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(.orange)
            
            // Content
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(miner?.hostName ?? "Unknown Miner")
                        .font(.system(size: 13, weight: .medium))
                    
                    if !actionLog.isRead {
                        Circle()
                            .fill(.blue)
                            .frame(width: 6, height: 6)
                    }
                }
                
                Text("Restarted due to low power")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Time
            Text(actionDate, format: .relative(presentation: .named))
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 6)
    }
}

// Keep the old verbose view for detail sheets if needed
struct WatchDogActionItemView: View {
    let actionLog: WatchDogActionLog
    let miners: [Miner]
    
    private var miner: Miner? {
        miners.first { $0.macAddress == actionLog.minerMacAddress }
    }
    
    private var formattedTime: String {
        let date = Date(timeIntervalSince1970: Double(actionLog.timestamp) / 1000.0)
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "arrow.clockwise.circle.fill")
                    .foregroundStyle(.orange)
                
                Text(miner?.hostName ?? "Unknown")
                    .font(.headline)
                
                Spacer()
                
                Text(formattedTime)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Text(actionLog.reason)
                .font(.callout)
                .foregroundStyle(.secondary)
            
            if let firmware = actionLog.minerFirmwareVersion {
                Text("Firmware: \(firmware)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding()
    }
}

// MARK: - Restart Chart View

private let kOneHourSeconds: TimeInterval = 3600
struct WatchDogRestartChart: View {
    let actionLogs: [WatchDogActionLog]
    let allMiners: [Miner]
    
    @State private var selectedDataPoint: ChartDataPoint?
    @State private var scrollPosition: ScrollPosition = ScrollPosition()
    
    struct ChartDataPoint: Identifiable, Equatable {
        let id: String
        let date: Date
        let count: Int
        let hour: String
        let actionLogs: [WatchDogActionLog]

        init(date: Date, count: Int, hour: String, actionLogs: [WatchDogActionLog]) {
            self.id = "\(date.timeIntervalSince1970)"
            self.date = date
            self.count = count
            self.hour = hour
            self.actionLogs = actionLogs
        }

        static func == (lhs: ChartDataPoint, rhs: ChartDataPoint) -> Bool {
            lhs.id == rhs.id
        }
    }
    
    private var chartData: [ChartDataPoint] {
        let calendar = Calendar.current
        let currentHour = calendar.dateInterval(of: .hour, for: Date())?.start ?? Date()
        let formatter = DateFormatter()
        formatter.timeStyle = .short

        // Calculate start time: 48 hours ago
        let startTime = calendar.date(byAdding: .hour, value: -48, to: currentHour) ?? currentHour.addingTimeInterval(-48 * kOneHourSeconds)

        // Group existing actions by hour
        let grouped = Dictionary(grouping: actionLogs) { actionLog in
            let date = Date(timeIntervalSince1970: Double(actionLog.timestamp) / 1000.0)
            return calendar.dateInterval(of: .hour, for: date)?.start ?? date
        }

        // Create data points for all hours in the last 48 hours
        var dataPoints: [ChartDataPoint] = []
        var currentIterHour = startTime

        while currentIterHour <= currentHour {
            let actionsForHour = grouped[currentIterHour] ?? []
            dataPoints.append(ChartDataPoint(
                date: currentIterHour,
                count: actionsForHour.count,
                hour: formatter.string(from: currentIterHour),
                actionLogs: actionsForHour
            ))
            currentIterHour = calendar.date(byAdding: .hour, value: 1, to: currentIterHour) ?? currentIterHour.addingTimeInterval(kOneHourSeconds)
        }

        // Set initial selection to most recent hour with data, or current hour
        if selectedDataPoint == nil {
            DispatchQueue.main.async {
                let barsWithData = dataPoints.filter { $0.count > 0 }
                selectedDataPoint = barsWithData.last ?? dataPoints.last
            }
        }

        return dataPoints
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            headerView
            
            if chartData.isEmpty {
                emptyChartView
            } else {
                chartAndCardView
            }
        }
    }
    
    private var headerView: some View {
        HStack {
            Image(systemName: "chart.bar.fill")
                .foregroundColor(.orange)
            Text("Restart Activity")
                .font(.headline)
                .fontWeight(.medium)
            Spacer()
            Text("\(actionLogs.count) total restarts")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private var emptyChartView: some View {
        Text("No data to display")
            .font(.caption)
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var chartAndCardView: some View {
        GeometryReader { geometry in
            HStack(spacing: 16) {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        chartView
                            .frame(height: geometry.size.height)
                    }
                    .frame(width: geometry.size.width - 276) // Total width minus card width (260) and spacing (16)
                    .scrollTargetLayout()
                    .scrollPosition($scrollPosition, anchor: .trailing)
                    .onChange(of: selectedDataPoint) {
                        guard let id: String = selectedDataPoint?.id else { return }

                        withAnimation {
                            proxy.scrollTo(id, anchor: .bottom)
                        }
                    }
                    .onAppear {
                        setupInitialSelection()
                        setupInitialScroll()
                    }
                }

                detailCardView
                    .frame(width: 260)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: selectedDataPoint)
    }

    private let selectedGradient = Gradient(colors: [Color.orange, Color.blue])
    private let unselectedGradient = Gradient(colors: [Color.orange, Color.orange.opacity(0.6)])

    private func gradient(isSelected: Bool) -> Gradient {
        return isSelected ? selectedGradient : unselectedGradient
    }
    private var chartView: some View {
        Chart(chartData, id: \.id) { point in
            let isSelected = selectedDataPoint?.date == point.date
            let barOpacity = point.count > 0 ? 1.0 : 0.3
            BarMark(
                x: .value("Time", point.date),
                y: .value("Restarts", point.count)
            )
            .foregroundStyle(gradient(isSelected: isSelected))
            .opacity(barOpacity)
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 1)) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(DateFormatter.shortTime.string(from: date))
                            .font(.system(size: 10))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel {
                    if let count = value.as(Int.self) {
                        Text("\(count)")
                            .font(.system(size: 10))
                    }
                }
            }
        }
        .chartYScale(domain: 0...(chartData.map(\.count).max() ?? 0) + 1)
        .chartGesture { chartProxy in
            SpatialTapGesture()
                .onEnded { value in
                    handleChartTap(location: value.location, chartProxy: chartProxy)
                }
        }
        .frame(width: CGFloat(chartData.count * 50))
    }
    
    private var detailCardView: some View {
        RestartDetailCard(
            dataPoint: selectedDataPoint,
            allMiners: allMiners,
            onDismiss: {
                selectedDataPoint = nil
            }
        )
    }
    
    private func setupInitialSelection() {
        if selectedDataPoint == nil {
            let barsWithData = chartData.filter { $0.count > 0 }
            if let mostRecent = barsWithData.first {
                selectedDataPoint = mostRecent
            }
        }
    }
    
    private func setupInitialScroll() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if let latestBar = chartData.first {
                scrollPosition.scrollTo(id: latestBar.id, anchor: .bottom)
            }
        }
    }
    
    private func handleChartTap(location: CGPoint, chartProxy: ChartProxy) {
        // Convert tap location to chart coordinates
        if let tappedDate: Date = chartProxy.value(atX: location.x) {
            // Find the closest data point to the tapped location
            let closestDataPoint = chartData.min { point1, point2 in
                abs(point1.date.timeIntervalSince(tappedDate)) < abs(point2.date.timeIntervalSince(tappedDate))
            }
            
            if let dataPoint = closestDataPoint {
                selectedDataPoint = dataPoint
            }
        }
    }
    
}

struct RestartDetailCard: View {
    let dataPoint: WatchDogRestartChart.ChartDataPoint?
    let allMiners: [Miner]
    let onDismiss: () -> Void
    
    private var minersForActions: [(miner: Miner?, action: WatchDogActionLog)] {
        guard let dataPoint = dataPoint else { return [] }
        return dataPoint.actionLogs.map { action in
            let miner = allMiners.first { $0.macAddress == action.minerMacAddress }
            return (miner: miner, action: action)
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    if let dataPoint = dataPoint {
                        Text("Restarts at \(dataPoint.hour)")
                            .font(.headline)
                            .fontWeight(.semibold)
                        Text("\(dataPoint.count) miners restarted")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Recent Restarts")
                            .font(.headline)
                            .fontWeight(.semibold)
                        Text("No recent activity")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
            }
            
            Divider()
            
            // Miner list or empty state
            if minersForActions.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "shield.checkered")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("No restart activity")
                        .font(.callout)
                        .foregroundColor(.secondary)
                    Text("WatchDog hasn't restarted any miners recently")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 100)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(minersForActions, id: \.action.id) { minerAction in
                            HStack(spacing: 6) {
                                Image(systemName: "cpu")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                                    .frame(width: 14)
                                
                                VStack(alignment: .leading, spacing: 1) {
                                    if let miner = minerAction.miner {
                                        Text(miner.hostName)
                                            .font(.caption)
                                            .fontWeight(.medium)
                                            .lineLimit(1)
                                        Text(miner.ipAddress)
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    } else {
                                        Text("Unknown Miner")
                                            .font(.caption)
                                            .fontWeight(.medium)
                                            .foregroundColor(.secondary)
                                        Text(minerAction.action.minerMacAddress.suffix(8))
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                
                                Spacer()
                                
                                // Exact time
                                Text(formatExactTime(minerAction.action.timestamp))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .fontDesign(.monospaced)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                            .cornerRadius(4)
                        }
                    }
                }
                .frame(maxHeight: 120)
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
    }
    
    private func formatExactTime(_ timestamp: Int64) -> String {
        let date = Date(timeIntervalSince1970: Double(timestamp) / 1000.0)
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
}

extension DateFormatter {
    static let shortTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h"
        return formatter
    }()
}

// MARK: - Watch Dog Tab Enum

enum WatchDogTab {
    case activity
    case poolAlerts
}

// MARK: - Pool Alerts Tab

struct PoolAlertsTab: View {
    @StateObject private var poolCoordinator = PoolMonitoringCoordinator.shared
    @Environment(\.modelContext) private var modelContext

    @State private var selectedAlert: PoolAlertEvent?
    @State private var showOnlyActive = true
    @State private var allAlerts: [PoolAlertEvent] = []

    var body: some View {
        VStack(spacing: 0) {
            // Monitoring Status
            HStack(spacing: 16) {
                // Monitored miners count
                HStack(spacing: 6) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .foregroundColor(poolCoordinator.monitoredMinerCount > 0 ? .green : .secondary)
                    Text("Monitoring \(poolCoordinator.monitoredMinerCount) miners")
                        .font(.callout)
                }

                Divider()
                    .frame(height: 16)

                // Last verification time
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle")
                        .foregroundColor(poolCoordinator.lastVerificationTime != nil ? .blue : .secondary)
                    if let lastTime = poolCoordinator.lastVerificationTime {
                        Text("Last verified \(lastTime, format: .relative(presentation: .named))")
                            .font(.callout)
                    } else {
                        Text("No verifications yet")
                            .font(.callout)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Filters
            HStack {
                Toggle("Active alerts only", isOn: $showOnlyActive)

                Spacer()

                if !alerts.isEmpty {
                    Button("Dismiss All") {
                        dismissAll()
                    }
                    .disabled(alerts.filter { !$0.isDismissed }.isEmpty)
                }
            }
            .padding()

            Divider()

            // Alert List
            if alerts.isEmpty {
                EmptyAlertsView(showOnlyActive: showOnlyActive)
            } else {
                List(alerts, selection: $selectedAlert) { alert in
                    PoolAlertRow(alert: alert)
                        .contextMenu {
                            Button("View Details") {
                                selectedAlert = alert
                            }

                            if !alert.isDismissed {
                                Button("Dismiss") {
                                    dismissAlert(alert)
                                }
                            }

                            Divider()

                            Button("Copy Pool Info") {
                                copyPoolInfo(alert)
                            }
                        }
                }
            }
        }
        .sheet(item: $selectedAlert) { alert in
            PoolAlertDetailView(alert: alert)
        }
        .task {
            await loadAllAlerts()
        }
        .onChange(of: showOnlyActive) { _, _ in
            Task {
                await loadAllAlerts()
            }
        }
    }

    private var alerts: [PoolAlertEvent] {
        showOnlyActive ? poolCoordinator.activeAlerts : allAlerts
    }

    private func loadAllAlerts() async {
        let service = PoolApprovalService(modelContext: modelContext)
        let alerts = await service.getAllAlerts(limit: 100)
        await MainActor.run {
            allAlerts = alerts
        }
    }

    private func dismissAlert(_ alert: PoolAlertEvent) {
        poolCoordinator.dismissAlert(alert, modelContext: modelContext)
    }

    private func dismissAll() {
        for alert in alerts where !alert.isDismissed {
            poolCoordinator.dismissAlert(alert, modelContext: modelContext)
        }
    }

    private func copyPoolInfo(_ alert: PoolAlertEvent) {
        let info = """
        Pool: \(alert.poolIdentifier)
        Miner: \(alert.minerHostname) (\(alert.minerIP))
        Time: \(alert.detectedAt.formatted())
        """

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(info, forType: .string)
    }
}

struct EmptyAlertsView: View {
    let showOnlyActive: Bool

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.shield.fill")
                .resizable()
                .frame(width: 60, height: 60)
                .foregroundColor(.green)

            Text(showOnlyActive ? "No Active Alerts" : "No Alert History")
                .font(.headline)

            Text("Pool outputs are being monitored for all verified miners.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    MinerWatchDogActionsView()
}
