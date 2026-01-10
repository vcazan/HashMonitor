//
//  MinerDetailView.swift
//  HashRipper-iOS
//
//  Comprehensive miner detail view matching macOS functionality
//

import SwiftUI
import SwiftData
import Charts
import HashRipperKit
import AxeOSClient

struct MinerDetailView: View {
    let miner: Miner
    
    @Environment(\.modelContext) private var modelContext
    @Query private var updates: [MinerUpdate]
    
    @State private var isRefreshing = false
    @State private var showSettings = false
    @State private var showLogs = false
    @State private var showRestartAlert = false
    @State private var isRestarting = false
    @State private var restartSuccess = false
    @State private var selectedChartTab = 0
    @State private var selectedTimeRange: ChartTimeRange = .oneHour
    @State private var refreshTimer: Timer?
    @State private var isInitialLoad = true
    @State private var selectedChartTime: Date? = nil
    
    // Chart polling interval from settings (default 1 second)
    @AppStorage("chartPollingInterval") private var chartPollingInterval = 1
    
    enum ChartTimeRange: String, CaseIterable {
        case oneHour = "1H"
        case eightHours = "8H"
        case twentyFourHours = "24H"
        
        var hours: Int {
            switch self {
            case .oneHour: return 1
            case .eightHours: return 8
            case .twentyFourHours: return 24
            }
        }
        
        var title: String {
            rawValue
        }
        
        var displayName: String {
            switch self {
            case .oneHour: return "Last Hour"
            case .eightHours: return "Last 8 Hours"
            case .twentyFourHours: return "Last 24 Hours"
            }
        }
    }
    
    init(miner: Miner) {
        self.miner = miner
        let macAddress = miner.macAddress
        _updates = Query(
            filter: #Predicate<MinerUpdate> { $0.macAddress == macAddress },
            sort: [SortDescriptor(\MinerUpdate.timestamp, order: .reverse)]
        )
    }
    
    private var latestUpdate: MinerUpdate? {
        updates.first
    }
    
    // Get updates for charts based on selected time range
    private var chartUpdates: [MinerUpdate] {
        let cutoffTime = Date().addingTimeInterval(-Double(selectedTimeRange.hours) * 3600)
        let cutoffTimestamp = Int64(cutoffTime.timeIntervalSince1970 * 1000)
        
        let filtered = updates.filter { $0.timestamp >= cutoffTimestamp }
        return Array(filtered.reversed())
    }
    
    // Check if we have any data at all (not time-range specific)
    private var hasAnyChartData: Bool {
        !updates.isEmpty
    }
    
    // Check if we have data for the selected time range
    private var hasDataForSelectedRange: Bool {
        chartUpdates.count >= 2
    }
    
    // The time domain for the chart (either actual data range or selected range)
    private var chartTimeDomain: ClosedRange<Date> {
        if chartUpdates.count >= 2,
           let first = chartUpdates.first,
           let last = chartUpdates.last {
            let startDate = Date(timeIntervalSince1970: TimeInterval(first.timestamp) / 1000)
            let endDate = Date(timeIntervalSince1970: TimeInterval(last.timestamp) / 1000)
            return startDate...endDate
        } else {
            // Show empty chart with the selected time range
            let endDate = Date()
            let startDate = endDate.addingTimeInterval(-Double(selectedTimeRange.hours) * 3600)
            return startDate...endDate
        }
    }
    
    // Get the best time range based on available data
    private var bestAvailableTimeRange: ChartTimeRange {
        for range in ChartTimeRange.allCases {
            let cutoffTime = Date().addingTimeInterval(-Double(range.hours) * 3600)
            let cutoffTimestamp = Int64(cutoffTime.timeIntervalSince1970 * 1000)
            let count = updates.filter { $0.timestamp >= cutoffTimestamp }.count
            if count >= 2 {
                return range
            }
        }
        return .oneHour
    }
    
    // Total data points collected
    private var totalDataPoints: Int {
        updates.count
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Header card
                headerCard
                
                if miner.isOffline && !isInitialLoad {
                    offlineCard
                } else if let update = latestUpdate {
                    // Main stats grid
                    mainStatsGrid(update: update)
                    
                    // Charts section
                    chartsSection
                    
                    // Shares section
                    sharesCard(update: update)
                    
                    // System info
                    systemInfoCard(update: update)
                    
                    // Actions
                    actionsCard
                } else if isInitialLoad {
                    // Loading state
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("Loading miner data...")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(40)
                }
            }
            .padding()
        }
        .navigationTitle(miner.hostName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    showLogs = true
                } label: {
                    Image(systemName: "terminal")
                }
                
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
            }
        }
        .refreshable {
            await refreshMiner()
        }
        .onAppear {
            startAutoRefresh()
            // Auto-select best time range based on available data
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                selectedTimeRange = bestAvailableTimeRange
            }
        }
        .onDisappear {
            stopAutoRefresh()
        }
        .onChange(of: chartPollingInterval) { _, _ in
            // Restart timer with new interval
            stopAutoRefresh()
            startAutoRefresh()
        }
        .sheet(isPresented: $showSettings) {
            MinerSettingsSheet(miner: miner)
        }
        .sheet(isPresented: $showLogs) {
            MinerLogsSheet(miner: miner)
        }
        .alert("Restart Miner?", isPresented: $showRestartAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Restart", role: .destructive) {
                Task { await restartMiner() }
            }
        } message: {
            Text("The miner will be temporarily offline while it reboots.")
        }
        .alert("Miner Restarted", isPresented: $restartSuccess) {
            Button("OK") { }
        } message: {
            Text("\(miner.hostName) is restarting.")
        }
    }
    
    // MARK: - Header Card
    
    private var headerCard: some View {
        VStack(spacing: 12) {
            // Top row: Icon, name, device type
            HStack(spacing: 16) {
                Image(miner.minerType.imageName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 56, height: 56)
                    .background(Color(.systemGray5))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(miner.hostName)
                            .font(.title3.bold())
                        
                        statusBadge
                    }
                    
                    Text(miner.minerDeviceDisplayName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    Link(destination: URL(string: "http://\(miner.ipAddress)")!) {
                        HStack(spacing: 4) {
                            Image(systemName: "globe")
                                .font(.caption2)
                            Text(miner.ipAddress)
                                .font(.caption.monospaced())
                        }
                        .foregroundStyle(.blue)
                    }
                }
                
                Spacer()
            }
            
            // Pool info row (if we have data)
            if let update = latestUpdate {
                Divider()
                
                HStack(spacing: 8) {
                    Image(systemName: "server.rack")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    let url = update.isUsingFallbackStratum ? update.fallbackStratumURL : update.stratumURL
                    let port = update.isUsingFallbackStratum ? update.fallbackStratumPort : update.stratumPort
                    
                    Text(verbatim: "\(url):\(port)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    
                    if update.isUsingFallbackStratum {
                        Text("FALLBACK")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.15))
                            .clipShape(Capsule())
                    }
                    
                    Spacer()
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    private var statusBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(miner.isOffline ? Color.red : Color.green)
                .frame(width: 8, height: 8)
            Text(miner.isOffline ? "Offline" : "Online")
                .font(.caption.weight(.medium))
        }
        .foregroundStyle(miner.isOffline ? .red : .green)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background((miner.isOffline ? Color.red : Color.green).opacity(0.15))
        .clipShape(Capsule())
    }
    
    // MARK: - Offline Card
    
    private var offlineCard: some View {
        VStack(spacing: 20) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 48))
                .foregroundStyle(.red.opacity(0.6))
            
            Text("Miner Offline")
                .font(.title2.bold())
            
            Text("Unable to connect to this miner")
                .foregroundStyle(.secondary)
            
            if let lastUpdate = latestUpdate {
                let date = Date(timeIntervalSince1970: TimeInterval(lastUpdate.timestamp) / 1000)
                Text("Last seen \(date.formatted(.relative(presentation: .named)))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            
            Button {
                Task { await refreshMiner() }
            } label: {
                HStack {
                    if isRefreshing {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                    Text(isRefreshing ? "Retrying..." : "Retry Connection")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isRefreshing)
        }
        .frame(maxWidth: .infinity)
        .padding(32)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    // MARK: - Main Stats Grid
    
    private func mainStatsGrid(update: MinerUpdate) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            let hashRate = formatMinerHashRate(rawRateValue: update.hashRate)
            StatTile(
                title: "Hash Rate",
                value: hashRate.rateString,
                unit: hashRate.rateSuffix,
                icon: "cube.fill",
                color: .green
            )
            
            StatTile(
                title: "Power",
                value: String(format: "%.1f", update.power),
                unit: "W",
                icon: "powerplug.fill",
                color: .orange
            )
            
            if let temp = update.temp {
                StatTile(
                    title: "ASIC Temp",
                    value: String(format: "%.1f", temp),
                    unit: "°C",
                    icon: "thermometer.medium",
                    color: tempColor(temp)
                )
            }
            
            if let vrTemp = update.vrTemp, vrTemp > 0 {
                StatTile(
                    title: "VR Temp",
                    value: String(format: "%.1f", vrTemp),
                    unit: "°C",
                    icon: "thermometer.low",
                    color: tempColor(vrTemp)
                )
            }
            
            if let frequency = update.frequency {
                StatTile(
                    title: "Frequency",
                    value: String(format: "%.0f", frequency),
                    unit: "MHz",
                    icon: "waveform",
                    color: .purple
                )
            }
            
            // Fan speed - show duty % or Auto
            if let fanSpeed = update.fanspeed {
                let isAuto = update.autofanspeed == 1
                StatTile(
                    title: isAuto ? "Fan (Auto)" : "Fan",
                    value: isAuto ? (update.fanrpm.map { "\($0)" } ?? "Auto") : String(format: "%.0f", fanSpeed),
                    unit: isAuto ? "RPM" : "%",
                    icon: "fan.fill",
                    color: .cyan
                )
            } else if let fanRPM = update.fanrpm {
                StatTile(
                    title: "Fan Speed",
                    value: "\(fanRPM)",
                    unit: "RPM",
                    icon: "fan.fill",
                    color: .cyan
                )
            }
        }
    }
    
    private func tempColor(_ temp: Double) -> Color {
        if temp >= 70 { return .red }
        if temp >= 55 { return .orange }
        return .green
    }
    
    // MARK: - Charts Section
    
    private var selectedUpdate: MinerUpdate? {
        guard let time = selectedChartTime else { return nil }
        return chartUpdates.min(by: {
            abs(Date(timeIntervalSince1970: TimeInterval($0.timestamp) / 1000).timeIntervalSince(time)) <
            abs(Date(timeIntervalSince1970: TimeInterval($1.timestamp) / 1000).timeIntervalSince(time))
        })
    }
    
    private var chartsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with time range and data count
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Performance")
                        .font(.headline)
                    Text("\(totalDataPoints) data points")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                
                Spacer()
                
                // Time range picker - compact segmented style
                Picker("Range", selection: $selectedTimeRange) {
                    ForEach(ChartTimeRange.allCases, id: \.self) { range in
                        Text(range.title).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 120)
                .onChange(of: selectedTimeRange) { _, _ in
                    selectedChartTime = nil
                }
            }
            
            // Chart type picker
            Picker("Chart", selection: $selectedChartTab) {
                Text("Hash Rate").tag(0)
                Text("Power").tag(1)
                Text("Temp").tag(2)
            }
            .pickerStyle(.segmented)
            .onChange(of: selectedChartTab) { _, _ in
                selectedChartTime = nil
            }
            
            // Chart content - always show chart with proper time axes
            if hasAnyChartData || totalDataPoints > 0 {
                // Chart with value badge overlay
                ZStack(alignment: .topTrailing) {
                    Group {
                        switch selectedChartTab {
                        case 0:
                            hashRateChart
                        case 1:
                            powerChart
                        case 2:
                            temperatureChart
                        default:
                            hashRateChart
                        }
                    }
                    .frame(height: 180)
                    
                    // Value badge in corner (only show when we have data selected)
                    if hasDataForSelectedRange {
                        selectedValueBadge
                            .padding(8)
                    }
                    
                    // Show "No data for this range" overlay when empty
                    if !hasDataForSelectedRange {
                        VStack(spacing: 4) {
                            Text("No data for \(selectedTimeRange.displayName.lowercased())")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if totalDataPoints > 0 {
                                Text("Try a shorter time range")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .padding(8)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                // Initial state - no data collected yet
                VStack(spacing: 12) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 32))
                        .foregroundStyle(.tertiary)
                    
                    Text("Collecting Data")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    
                    Text("Charts will appear after data is collected.\nRefreshing every \(chartPollingInterval) second\(chartPollingInterval == 1 ? "" : "s").")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                    
                    ProgressView()
                        .scaleEffect(0.8)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 180)
                .padding()
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }
    
    @ViewBuilder
    private var selectedValueBadge: some View {
        VStack(alignment: .trailing, spacing: 2) {
            if let update = selectedUpdate {
                let time = Date(timeIntervalSince1970: TimeInterval(update.timestamp) / 1000)
                
                Group {
                    switch selectedChartTab {
                    case 0:
                        let hashRate = formatMinerHashRate(rawRateValue: update.hashRate)
                        Text("\(hashRate.rateString) \(hashRate.rateSuffix)")
                    case 1:
                        Text(String(format: "%.1f W", update.power))
                    case 2:
                        if let temp = update.temp {
                            Text(String(format: "%.1f°C", temp))
                        } else {
                            Text("--")
                        }
                    default:
                        Text("--")
                    }
                }
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(.blue)
                
                Text(time, format: .dateTime.hour().minute().second())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                // Placeholder to reserve space - invisible but same size
                Text("00.0 TH/s")
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(.clear)
                
                Text("00:00:00 PM")
                    .font(.caption2)
                    .foregroundStyle(.clear)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(selectedUpdate != nil ? Color.blue.opacity(0.1) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .animation(.easeInOut(duration: 0.15), value: selectedUpdate != nil)
    }
    
    // Determine the best unit for displaying hash rates in the chart
    // Note: API returns hashRate in GH/s, so we multiply by 1 billion to get H/s first
    private var hashRateUnit: (divisor: Double, label: String) {
        guard let maxRate = chartUpdates.map({ $0.hashRate }).max(), maxRate > 0 else {
            return (1, "GH/s") // Default to GH/s since API returns in GH/s
        }
        
        // Convert from API units (GH/s) to H/s
        let maxRateInH = maxRate * 1_000_000_000
        
        if maxRateInH >= 1_000_000_000_000_000 { // >= 1 PH/s
            return (1_000_000, "PH/s") // Divide API value by 1M to get PH/s
        } else if maxRateInH >= 1_000_000_000_000 { // >= 1 TH/s
            return (1_000, "TH/s") // Divide API value by 1K to get TH/s
        } else if maxRateInH >= 1_000_000_000 { // >= 1 GH/s
            return (1, "GH/s") // API already in GH/s
        } else if maxRateInH >= 1_000_000 { // >= 1 MH/s
            return (0.001, "MH/s") // Multiply API value by 1K to get MH/s
        }
        return (0.000001, "KH/s")
    }
    
    private var hashRateChart: some View {
        let unit = hashRateUnit
        let domain = chartTimeDomain
        
        return Chart {
            ForEach(chartUpdates, id: \.timestamp) { update in
                let date = Date(timeIntervalSince1970: TimeInterval(update.timestamp) / 1000)
                // API returns GH/s, convert to display unit
                let value = update.hashRate / unit.divisor
                
                LineMark(
                    x: .value("Time", date),
                    y: .value("Hash Rate", value)
                )
                .foregroundStyle(.green)
                .interpolationMethod(.catmullRom)
                
                AreaMark(
                    x: .value("Time", date),
                    y: .value("Hash Rate", value)
                )
                .foregroundStyle(.green.opacity(0.1))
                .interpolationMethod(.catmullRom)
            }
            
            // Selection indicator
            if let selected = selectedUpdate {
                let date = Date(timeIntervalSince1970: TimeInterval(selected.timestamp) / 1000)
                let value = selected.hashRate / unit.divisor
                
                RuleMark(x: .value("Selected", date))
                    .foregroundStyle(Color.primary.opacity(0.3))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                
                PointMark(
                    x: .value("Time", date),
                    y: .value("Hash Rate", value)
                )
                .foregroundStyle(.green)
                .symbolSize(80)
            }
        }
        .chartXScale(domain: domain)
        .chartXSelection(value: $selectedChartTime)
        .chartYAxisLabel(unit.label)
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let val = value.as(Double.self) {
                        Text(String(format: "%.1f", val))
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.hour().minute())
            }
        }
    }
    
    private var powerChart: some View {
        let domain = chartTimeDomain
        
        return Chart {
            ForEach(chartUpdates, id: \.timestamp) { update in
                let date = Date(timeIntervalSince1970: TimeInterval(update.timestamp) / 1000)
                LineMark(
                    x: .value("Time", date),
                    y: .value("Power", update.power)
                )
                .foregroundStyle(.orange)
                .interpolationMethod(.catmullRom)
                
                AreaMark(
                    x: .value("Time", date),
                    y: .value("Power", update.power)
                )
                .foregroundStyle(.orange.opacity(0.1))
                .interpolationMethod(.catmullRom)
            }
            
            // Selection indicator
            if let selected = selectedUpdate {
                let date = Date(timeIntervalSince1970: TimeInterval(selected.timestamp) / 1000)
                
                RuleMark(x: .value("Selected", date))
                    .foregroundStyle(Color.primary.opacity(0.3))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                
                PointMark(
                    x: .value("Time", date),
                    y: .value("Power", selected.power)
                )
                .foregroundStyle(.orange)
                .symbolSize(80)
            }
        }
        .chartXScale(domain: domain)
        .chartXSelection(value: $selectedChartTime)
        .chartYAxisLabel("W")
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let val = value.as(Double.self) {
                        Text(String(format: "%.0f", val))
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.hour().minute())
            }
        }
    }
    
    private var temperatureChart: some View {
        let domain = chartTimeDomain
        
        return Chart {
            ForEach(chartUpdates, id: \.timestamp) { update in
                let date = Date(timeIntervalSince1970: TimeInterval(update.timestamp) / 1000)
                if let temp = update.temp {
                    LineMark(
                        x: .value("Time", date),
                        y: .value("ASIC", temp),
                        series: .value("Type", "ASIC")
                    )
                    .foregroundStyle(.orange)
                    .interpolationMethod(.catmullRom)
                }
                
                if let vrTemp = update.vrTemp, vrTemp > 0 {
                    LineMark(
                        x: .value("Time", date),
                        y: .value("VR", vrTemp),
                        series: .value("Type", "VR")
                    )
                    .foregroundStyle(.blue)
                    .interpolationMethod(.catmullRom)
                }
            }
            
            // Selection indicator
            if let selected = selectedUpdate {
                let date = Date(timeIntervalSince1970: TimeInterval(selected.timestamp) / 1000)
                
                RuleMark(x: .value("Selected", date))
                    .foregroundStyle(Color.primary.opacity(0.3))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                
                if let temp = selected.temp {
                    PointMark(
                        x: .value("Time", date),
                        y: .value("ASIC", temp)
                    )
                    .foregroundStyle(.orange)
                    .symbolSize(80)
                }
                
                if let vrTemp = selected.vrTemp, vrTemp > 0 {
                    PointMark(
                        x: .value("Time", date),
                        y: .value("VR", vrTemp)
                    )
                    .foregroundStyle(.blue)
                    .symbolSize(80)
                }
            }
        }
        .chartXScale(domain: domain)
        .chartXSelection(value: $selectedChartTime)
        .chartYAxisLabel("°C")
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let val = value.as(Double.self) {
                        Text(String(format: "%.0f°", val))
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.hour().minute())
            }
        }
        .chartLegend(position: .top)
    }
    
    // MARK: - Shares Card
    
    private func sharesCard(update: MinerUpdate) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Mining Stats")
                .font(.headline)
            
            HStack(spacing: 20) {
                AnimatedShareCounter(
                    value: update.sharesAccepted ?? 0,
                    label: "Accepted",
                    color: .green
                )
                
                AnimatedShareCounter(
                    value: update.sharesRejected ?? 0,
                    label: "Rejected",
                    color: (update.sharesRejected ?? 0) > 0 ? .red : .gray,
                    isAlert: (update.sharesRejected ?? 0) > 0
                )
                
                Spacer()
            }
            
            Divider()
            
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Best Difficulty")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(update.bestDiff ?? "—")
                        .font(.system(.body, design: .monospaced, weight: .semibold))
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Session Best")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(update.bestSessionDiff ?? "—")
                        .font(.system(.body, design: .monospaced, weight: .semibold))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    // MARK: - System Info Card
    
    private func systemInfoCard(update: MinerUpdate) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("System")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.top, 12)
                .padding(.bottom, 8)
            
            VStack(spacing: 0) {
                SystemInfoRow(icon: "info.circle", label: "Firmware", value: update.minerFirmwareVersion)
                
                Divider().padding(.leading, 44)
                
                SystemInfoRow(icon: "cpu", label: "ASIC", value: update.axeOSVersion ?? "—")
                
                Divider().padding(.leading, 44)
                
                SystemInfoRow(icon: "clock", label: "Uptime", value: formatUptime(update.uptimeSeconds ?? 0))
                
                Divider().padding(.leading, 44)
                
                SystemInfoRow(icon: "network", label: "MAC Address", value: miner.macAddress)
                
                if let fanSpeed = update.fanspeed {
                    Divider().padding(.leading, 44)
                    SystemInfoRow(icon: "fan", label: "Fan Duty", value: String(format: "%.0f%%", fanSpeed))
                }
                
                if let voltage = update.voltage {
                    Divider().padding(.leading, 44)
                    SystemInfoRow(icon: "bolt", label: "Voltage", value: String(format: "%.2fV", voltage))
                }
                
                if let coreVoltage = update.coreVoltage {
                    Divider().padding(.leading, 44)
                    SystemInfoRow(icon: "bolt.circle", label: "Core Voltage", value: "\(coreVoltage) mV")
                }
            }
            .padding(.bottom, 4)
        }
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    private func formatUptime(_ seconds: Int) -> String {
        let days = seconds / 86400
        let hours = (seconds % 86400) / 3600
        let minutes = (seconds % 3600) / 60
        
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }
    
    // MARK: - Actions Card
    
    private var actionsCard: some View {
        VStack(spacing: 12) {
            Button {
                showRestartAlert = true
            } label: {
                HStack {
                    if isRestarting {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                    Text(isRestarting ? "Restarting..." : "Restart Miner")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .disabled(isRestarting || miner.isOffline)
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    // MARK: - Actions
    
    private func refreshMiner() async {
        isRefreshing = true
        defer { isRefreshing = false }
        
        let client = AxeOSClient(
            deviceIpAddress: miner.ipAddress,
            urlSession: .shared
        )
        
        let result = await client.getSystemInfo()
        
        switch result {
        case .success(let info):
            miner.consecutiveTimeoutErrors = 0
            
            let update = MinerUpdate(
                miner: miner,
                hostname: info.hostname,
                stratumUser: info.stratumUser ?? "",
                fallbackStratumUser: info.fallbackStratumUser ?? "",
                stratumURL: info.stratumURL ?? "",
                stratumPort: info.stratumPort ?? 0,
                fallbackStratumURL: info.fallbackStratumURL ?? "",
                fallbackStratumPort: info.fallbackStratumPort ?? 0,
                minerFirmwareVersion: info.version ?? "Unknown",
                axeOSVersion: info.ASICModel,
                bestDiff: info.bestDiff,
                bestSessionDiff: info.bestSessionDiff,
                frequency: info.frequency,
                temp: info.temp,
                vrTemp: info.vrTemp,
                fanrpm: info.fanrpm,
                fanspeed: info.fanspeed,
                hashRate: info.hashRate ?? 0,
                power: info.power ?? 0,
                sharesAccepted: info.sharesAccepted,
                sharesRejected: info.sharesRejected,
                uptimeSeconds: info.uptimeSeconds,
                isUsingFallbackStratum: info.isUsingFallbackStratum ?? false
            )
            modelContext.insert(update)
            
        case .failure:
            miner.consecutiveTimeoutErrors += 1
        }
    }
    
    private func restartMiner() async {
        isRestarting = true
        defer { isRestarting = false }
        
        let client = AxeOSClient(
            deviceIpAddress: miner.ipAddress,
            urlSession: .shared
        )
        
        let result = await client.restartClient()
        
        if case .success = result {
            restartSuccess = true
        }
    }
    
    // MARK: - Auto Refresh
    
    private func startAutoRefresh() {
        // Immediate fetch on appear
        Task {
            await refreshMiner()
            isInitialLoad = false
        }
        
        // Set up periodic refresh timer
        refreshTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(chartPollingInterval), repeats: true) { _ in
            Task {
                await refreshMiner()
            }
        }
    }
    
    private func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
}

// MARK: - Supporting Views

struct StatTile: View {
    let title: String
    let value: String
    let unit: String
    let icon: String
    let color: Color
    
    @State private var isHighlighted = false
    @State private var previousValue: String = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .foregroundStyle(color)
                    .contentTransition(.numericText(value: Double(value) ?? 0))
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: value)
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            ZStack {
                Color(.systemGray6)
                RoundedRectangle(cornerRadius: 12)
                    .fill(color.opacity(isHighlighted ? 0.15 : 0))
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
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

struct InfoTile: View {
    let label: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.callout, design: .monospaced))
                .lineLimit(1)
        }
    }
}

struct SystemInfoRow: View {
    let icon: String
    let label: String
    let value: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .frame(width: 24)
            
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.primary)
            
            Spacer()
            
            Text(value)
                .font(.system(.subheadline, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }
}

struct AnimatedShareCounter: View {
    let value: Int
    let label: String
    let color: Color
    var isAlert: Bool = false
    
    @State private var isHighlighted = false
    @State private var previousValue: Int = 0
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                    .scaleEffect(isHighlighted ? 1.4 : 1.0)
                    .animation(.spring(response: 0.25, dampingFraction: 0.5), value: isHighlighted)
                
                Text("\(value)")
                    .font(.system(.title2, design: .monospaced, weight: .bold))
                    .foregroundStyle(isAlert ? color : .primary)
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: value)
            }
            Text(label)
                .font(.caption)
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

// MARK: - Logs Sheet

enum LogLevel: String, CaseIterable, Identifiable {
    case error = "E"
    case warning = "W"
    case info = "I"
    case debug = "D"
    case verbose = "V"
    
    var id: String { rawValue }
    
    var label: String {
        switch self {
        case .error: return "Error"
        case .warning: return "Warning"
        case .info: return "Info"
        case .debug: return "Debug"
        case .verbose: return "Verbose"
        }
    }
    
    var color: Color {
        switch self {
        case .error: return .red
        case .warning: return .orange
        case .info: return .blue
        case .debug: return .gray
        case .verbose: return .purple
        }
    }
    
    var icon: String {
        switch self {
        case .error: return "xmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        case .debug: return "ladybug.fill"
        case .verbose: return "text.alignleft"
        }
    }
    
    // Map from ANSI color codes used by miner firmware
    init?(colorCode: Int) {
        switch colorCode {
        case 31: self = .error    // Red
        case 33: self = .warning  // Yellow
        case 32: self = .info     // Green
        case 36: self = .debug    // Cyan
        case 37: self = .verbose  // White
        default: return nil
        }
    }
}

struct LogEntry: Identifiable {
    let id: UUID
    let timestamp: Date
    let level: LogLevel
    let component: String
    let message: String
    let uptimeMs: TimeInterval  // Miner uptime in ms
    
    init(id: UUID = UUID(), timestamp: Date = Date(), level: LogLevel, component: String, message: String, uptimeMs: TimeInterval = 0) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.component = component
        self.message = message
        self.uptimeMs = uptimeMs
    }
}

// MARK: - WebSocket Log Parser

actor WebSocketLogParser {
    // Pattern with ANSI color codes: [0;32mI (12345) component: message[0m
    private static let ansiPattern = #"\[([0-9;]+)m([A-Z]) \((\d+)\) ([^:]+): (.+)\[0m"#
    private static let ansiRegex = try! NSRegularExpression(pattern: ansiPattern)
    
    // Plain text pattern: I (12345) component: message
    private static let plainPattern = #"^([A-Z]) \((\d+)\) ([^:]+): (.+)$"#
    private static let plainRegex = try! NSRegularExpression(pattern: plainPattern)

    func parse(_ rawText: String) -> LogEntry? {
        // Try ANSI pattern first
        if let entry = parseAnsi(rawText) {
            return entry
        }
        
        // Fall back to plain text pattern
        if let entry = parsePlain(rawText) {
            return entry
        }
        
        return nil
    }
    
    private func parseAnsi(_ rawText: String) -> LogEntry? {
        let nsString = rawText as NSString
        guard let match = Self.ansiRegex.firstMatch(
            in: rawText,
            range: NSRange(location: 0, length: nsString.length)
        ), match.numberOfRanges == 6 else {
            return nil
        }

        let ansiColorCode = nsString.substring(with: match.range(at: 1))
        let levelChar = nsString.substring(with: match.range(at: 2))
        let timestampStr = nsString.substring(with: match.range(at: 3))
        let componentStr = nsString.substring(with: match.range(at: 4))
        let message = nsString.substring(with: match.range(at: 5))

        // Extract color code number from ANSI sequence (e.g., "0;32" → 32)
        let colorCode: Int
        let parts = ansiColorCode.split(separator: ";")
        if parts.count == 2, let code = Int(parts[1]) {
            colorCode = code
        } else {
            colorCode = 37  // Default to white/verbose
        }

        guard let uptimeMs = TimeInterval(timestampStr),
              let level = LogLevel(colorCode: colorCode) ?? LogLevel(rawValue: levelChar) else {
            return nil
        }

        return LogEntry(
            id: UUID(),
            timestamp: Date(),
            level: level,
            component: componentStr,
            message: message,
            uptimeMs: uptimeMs
        )
    }
    
    private func parsePlain(_ rawText: String) -> LogEntry? {
        let nsString = rawText as NSString
        guard let match = Self.plainRegex.firstMatch(
            in: rawText,
            range: NSRange(location: 0, length: nsString.length)
        ), match.numberOfRanges == 5 else {
            return nil
        }

        let levelChar = nsString.substring(with: match.range(at: 1))
        let timestampStr = nsString.substring(with: match.range(at: 2))
        let componentStr = nsString.substring(with: match.range(at: 3))
        let message = nsString.substring(with: match.range(at: 4))

        guard let uptimeMs = TimeInterval(timestampStr),
              let level = LogLevel(rawValue: levelChar) else {
            return nil
        }

        return LogEntry(
            id: UUID(),
            timestamp: Date(),
            level: level,
            component: componentStr,
            message: message,
            uptimeMs: uptimeMs
        )
    }
}

// MARK: - Logs ViewModel

@MainActor
class LogsViewModel: ObservableObject {
    let miner: Miner
    
    @Published var logEntries: [LogEntry] = []
    @Published var isConnecting = true
    @Published var isConnected = false
    @Published var connectionError: String?
    
    private var websocketClient: AxeOSWebsocketClient?
    private var messageTask: Task<Void, Never>?
    private var connectionTask: Task<Void, Never>?
    private let parser = WebSocketLogParser()
    
    init(miner: Miner) {
        self.miner = miner
    }
    
    func connect() {
        guard websocketClient == nil else { return }
        
        isConnecting = true
        isConnected = false
        connectionError = nil
        
        let client = AxeOSWebsocketClient()
        self.websocketClient = client
        
        // Start connection
        connectionTask = Task {
            let url = URL(string: "ws://\(miner.ipAddress)/api/ws")!
            await client.connect(to: url)
            
            // Monitor connection state
            for await state in await client.connectionStatePublisher.values {
                await MainActor.run {
                    switch state {
                    case .connected:
                        self.isConnecting = false
                        self.isConnected = true
                        self.connectionError = nil
                    case .connecting:
                        self.isConnecting = true
                        self.isConnected = false
                    case .disconnected:
                        self.isConnecting = false
                        self.isConnected = false
                    case .reconnecting(let attempt):
                        self.isConnecting = true
                        self.isConnected = false
                        self.connectionError = "Reconnecting (attempt \(attempt))..."
                    case .failed(let reason):
                        self.isConnecting = false
                        self.isConnected = false
                        self.connectionError = reason
                    }
                }
            }
        }
        
        // Start message processing
        messageTask = Task {
            for await message in await client.messagePublisher.values {
                let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                
                if let entry = await parser.parse(trimmed) {
                    await MainActor.run {
                        self.logEntries.append(entry)
                        // Keep max 500 entries to prevent memory issues
                        if self.logEntries.count > 500 {
                            self.logEntries.removeFirst(self.logEntries.count - 500)
                        }
                    }
                }
            }
        }
    }
    
    func disconnect() {
        messageTask?.cancel()
        messageTask = nil
        connectionTask?.cancel()
        connectionTask = nil
        
        Task {
            await websocketClient?.close()
            websocketClient = nil
        }
        
        isConnected = false
        isConnecting = false
    }
    
    func clearLogs() {
        logEntries.removeAll()
    }
    
    deinit {
        messageTask?.cancel()
        connectionTask?.cancel()
    }
}

struct MinerLogsSheet: View {
    let miner: Miner
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: LogsViewModel
    
    @State private var searchText = ""
    @State private var selectedLevels: Set<LogLevel> = Set(LogLevel.allCases)
    @State private var selectedComponent: String? = nil
    @State private var autoScroll = true
    
    init(miner: Miner) {
        self.miner = miner
        _viewModel = StateObject(wrappedValue: LogsViewModel(miner: miner))
    }
    
    private var availableComponents: [String] {
        Array(Set(viewModel.logEntries.map { $0.component })).sorted()
    }
    
    private var filteredEntries: [LogEntry] {
        viewModel.logEntries.filter { entry in
            // Level filter
            guard selectedLevels.contains(entry.level) else { return false }
            
            // Component filter
            if let component = selectedComponent, entry.component != component {
                return false
            }
            
            // Search filter
            if !searchText.isEmpty {
                let searchLower = searchText.lowercased()
                return entry.message.lowercased().contains(searchLower) ||
                       entry.component.lowercased().contains(searchLower)
            }
            
            return true
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Connection status bar
                connectionStatusBar
                
                // Filter bar
                filterBar
                
                Divider()
                
                // Log entries
                if filteredEntries.isEmpty {
                    ContentUnavailableView {
                        Label(viewModel.isConnecting ? "Connecting..." : "No Logs", systemImage: "terminal")
                    } description: {
                        if viewModel.isConnecting {
                            Text("Connecting to \(miner.hostName)...")
                        } else if viewModel.logEntries.isEmpty {
                            Text("Waiting for log entries...")
                        } else {
                            Text("No logs match your filters")
                        }
                    }
                } else {
                    logEntriesView
                }
            }
            .navigationTitle("Logs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            autoScroll.toggle()
                        } label: {
                            Label(autoScroll ? "Auto-scroll On" : "Auto-scroll Off",
                                  systemImage: autoScroll ? "checkmark" : "")
                        }
                        
                        Button(role: .destructive) {
                            viewModel.clearLogs()
                        } label: {
                            Label("Clear Logs", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .onAppear {
            viewModel.connect()
        }
        .onDisappear {
            viewModel.disconnect()
        }
    }
    
    // MARK: - Connection Status Bar
    
    private var connectionStatusBar: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(viewModel.isConnected ? Color.green : (viewModel.isConnecting ? Color.orange : Color.red))
                .frame(width: 8, height: 8)
            
            if let error = viewModel.connectionError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else {
                Text(viewModel.isConnected ? "Connected" : (viewModel.isConnecting ? "Connecting..." : "Disconnected"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Text("\(filteredEntries.count) entries")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
    }
    
    // MARK: - Filter Bar
    
    private var filterBar: some View {
        VStack(spacing: 8) {
            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Filter logs...", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(8)
            .background(Color(.systemGray5))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            
            // Level filters
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(LogLevel.allCases) { level in
                        LogLevelFilterChip(
                            level: level,
                            isSelected: selectedLevels.contains(level),
                            action: {
                                if selectedLevels.contains(level) {
                                    selectedLevels.remove(level)
                                } else {
                                    selectedLevels.insert(level)
                                }
                            }
                        )
                    }
                    
                    Divider()
                        .frame(height: 20)
                    
                    // Component filter
                    Menu {
                        Button("All Components") {
                            selectedComponent = nil
                        }
                        Divider()
                        ForEach(availableComponents, id: \.self) { component in
                            Button(component) {
                                selectedComponent = component
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "cube")
                                .font(.caption)
                            Text(selectedComponent ?? "All")
                                .font(.caption)
                            Image(systemName: "chevron.down")
                                .font(.caption2)
                        }
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(.systemGray5))
                        .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
    
    // MARK: - Log Entries View
    
    private var logEntriesView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(filteredEntries) { entry in
                        LogEntryRow(entry: entry)
                            .id(entry.id)
                    }
                }
                .padding(.vertical, 4)
            }
            .background(Color(.systemBackground))
            .onChange(of: filteredEntries.count) { _, _ in
                if autoScroll, let last = filteredEntries.last {
                    withAnimation(.easeOut(duration: 0.1)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }
    
}

// MARK: - Log Level Filter Chip

struct LogLevelFilterChip: View {
    let level: LogLevel
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: level.icon)
                    .font(.system(size: 10))
                Text(level.label)
                    .font(.caption)
            }
            .foregroundStyle(isSelected ? .white : level.color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isSelected ? level.color : level.color.opacity(0.15))
            .clipShape(Capsule())
        }
    }
}

// MARK: - Log Entry Row

struct LogEntryRow: View {
    let entry: LogEntry
    
    private var timeString: String {
        // Show miner uptime in HH:MM:SS format if available
        if entry.uptimeMs > 0 {
            let totalSeconds = Int(entry.uptimeMs / 1000)
            let hours = totalSeconds / 3600
            let minutes = (totalSeconds % 3600) / 60
            let seconds = totalSeconds % 60
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        }
        return entry.timestamp.formatted(.dateTime.hour().minute().second())
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Timestamp (miner uptime)
            Text(timeString)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 60, alignment: .leading)
            
            // Level indicator
            Image(systemName: entry.level.icon)
                .font(.system(size: 10))
                .foregroundStyle(entry.level.color)
                .frame(width: 16)
            
            // Component
            Text(entry.component)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(minWidth: 50, alignment: .leading)
                .lineLimit(1)
            
            // Message
            Text(entry.message)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(entry.level == .error ? Color.red.opacity(0.1) :
                    entry.level == .warning ? Color.orange.opacity(0.05) : Color.clear)
    }
}

#Preview {
    NavigationStack {
        MinerDetailView(miner: Miner(
            hostName: "test-miner",
            ipAddress: "192.168.1.100",
            ASICModel: "BM1366",
            boardVersion: "600",
            macAddress: "AA:BB:CC:DD:EE:FF"
        ))
    }
    .modelContainer(try! createModelContainer(inMemory: true))
}
