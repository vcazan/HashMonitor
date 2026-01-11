//
//  MinerDetailView.swift
//  HashRipper-iOS
//
//  Professional miner detail view with muted, sophisticated design
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
    
    private var latestUpdate: MinerUpdate? { updates.first }
    
    private var chartUpdates: [MinerUpdate] {
        let cutoffTime = Date().addingTimeInterval(-Double(selectedTimeRange.hours) * 3600)
        let cutoffTimestamp = Int64(cutoffTime.timeIntervalSince1970 * 1000)
        return Array(updates.filter { $0.timestamp >= cutoffTimestamp }.reversed())
    }
    
    private var hasAnyChartData: Bool { !updates.isEmpty }
    private var hasDataForSelectedRange: Bool { chartUpdates.count >= 2 }
    
    private var chartTimeDomain: ClosedRange<Date> {
        if chartUpdates.count >= 2,
           let first = chartUpdates.first,
           let last = chartUpdates.last {
            return Date(timeIntervalSince1970: TimeInterval(first.timestamp) / 1000)...Date(timeIntervalSince1970: TimeInterval(last.timestamp) / 1000)
        }
        let endDate = Date()
        return endDate.addingTimeInterval(-Double(selectedTimeRange.hours) * 3600)...endDate
    }
    
    private var bestAvailableTimeRange: ChartTimeRange {
        for range in ChartTimeRange.allCases {
            let cutoffTimestamp = Int64(Date().addingTimeInterval(-Double(range.hours) * 3600).timeIntervalSince1970 * 1000)
            if updates.filter({ $0.timestamp >= cutoffTimestamp }).count >= 2 { return range }
        }
        return .oneHour
    }
    
    // MARK: - Body
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                headerCard
                
                if miner.isOffline && !isInitialLoad {
                    offlineCard
                } else if let update = latestUpdate {
                    statsGrid(update: update)
                    chartsSection
                    miningStatsCard(update: update)
                    systemInfoCard(update: update)
                    actionsCard
                } else if isInitialLoad {
                    loadingView
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(miner.hostName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { showLogs = true } label: {
                    Image(systemName: "terminal")
                }
                Button { showSettings = true } label: {
                    Image(systemName: "slider.horizontal.3")
                }
            }
        }
        .refreshable { await refreshMiner() }
        .onAppear {
            startAutoRefresh()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                selectedTimeRange = bestAvailableTimeRange
            }
        }
        .onDisappear { stopAutoRefresh() }
        .onChange(of: chartPollingInterval) { _, _ in
            stopAutoRefresh()
            startAutoRefresh()
        }
        .sheet(isPresented: $showSettings) { MinerSettingsSheet(miner: miner) }
        .sheet(isPresented: $showLogs) { MinerLogsSheet(miner: miner) }
        .alert("Restart Miner?", isPresented: $showRestartAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Restart", role: .destructive) { Task { await restartMiner() } }
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
            HStack(spacing: 14) {
                Image(miner.minerType.imageName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 52, height: 52)
                    .background(Color(.tertiarySystemFill))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(miner.hostName)
                            .font(.system(size: 17, weight: .semibold))
                        StatusBadge(isOnline: !miner.isOffline, compact: true)
                    }
                    
                    Text(miner.minerDeviceDisplayName)
                        .font(.system(size: 13))
                        .foregroundStyle(AppColors.subtleText)
                    
                    Link(destination: URL(string: "http://\(miner.ipAddress)")!) {
                        HStack(spacing: 3) {
                            Image(systemName: "globe")
                                .font(.system(size: 10))
                            Text(miner.ipAddress)
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                        }
                        .foregroundStyle(AppColors.accent)
                    }
                }
                
                Spacer()
            }
            
            if let update = latestUpdate {
                Divider()
                
                HStack(spacing: 6) {
                    Image(systemName: "server.rack")
                        .font(.system(size: 11))
                        .foregroundStyle(AppColors.subtleText)
                    
                    let url = update.isUsingFallbackStratum ? update.fallbackStratumURL : update.stratumURL
                    let port = update.isUsingFallbackStratum ? update.fallbackStratumPort : update.stratumPort
                    
                    Text(verbatim: "\(url):\(port)")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    
                    if update.isUsingFallbackStratum {
                        Text("FALLBACK")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(AppColors.warning)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(AppColors.warningLight)
                            .clipShape(Capsule())
                    }
                    
                    Spacer()
                }
            }
        }
        .padding(14)
        .cardStyle()
    }
    
    // MARK: - Offline Card
    
    private var offlineCard: some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(AppColors.error.opacity(0.7))
            
            VStack(spacing: 4) {
                Text("Miner Offline")
                    .font(.system(size: 17, weight: .semibold))
                
                Text("Unable to connect to this miner")
                    .font(.system(size: 14))
                    .foregroundStyle(AppColors.subtleText)
            }
            
            if let lastUpdate = latestUpdate {
                let date = Date(timeIntervalSince1970: TimeInterval(lastUpdate.timestamp) / 1000)
                Text("Last seen \(date.formatted(.relative(presentation: .named)))")
                    .font(.system(size: 12))
                    .foregroundStyle(AppColors.mutedText)
            }
            
            Button {
                Task { await refreshMiner() }
            } label: {
                HStack(spacing: 6) {
                    if isRefreshing {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                    Text(isRefreshing ? "Retrying..." : "Retry Connection")
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(AppColors.accent)
            .disabled(isRefreshing)
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .cardStyle()
    }
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading miner data...")
                .font(.system(size: 14))
                .foregroundStyle(AppColors.subtleText)
        }
        .frame(maxWidth: .infinity)
        .padding(36)
    }
    
    // MARK: - Stats Grid
    
    private func statsGrid(update: MinerUpdate) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            let hashRate = formatMinerHashRate(rawRateValue: update.hashRate)
            StatCard(title: "Hash Rate", value: hashRate.rateString, unit: hashRate.rateSuffix, icon: "cube.fill", color: AppColors.hashRate)
            
            StatCard(title: "Power", value: String(format: "%.1f", update.power), unit: "W", icon: "bolt.fill", color: AppColors.power)
            
            if let temp = update.temp {
                StatCard(title: "ASIC Temp", value: String(format: "%.1f", temp), unit: "°C", icon: "thermometer.medium", color: temperatureColor(temp))
            }
            
            if let vrTemp = update.vrTemp, vrTemp > 0 {
                StatCard(title: "VR Temp", value: String(format: "%.1f", vrTemp), unit: "°C", icon: "thermometer.low", color: temperatureColor(vrTemp))
            }
            
            if let frequency = update.frequency {
                StatCard(title: "Frequency", value: String(format: "%.0f", frequency), unit: "MHz", icon: "waveform", color: AppColors.frequency)
            }
            
            if let fanSpeed = update.fanspeed {
                let isAuto = update.autofanspeed == 1
                StatCard(
                    title: isAuto ? "Fan (Auto)" : "Fan",
                    value: isAuto ? (update.fanrpm.map { "\($0)" } ?? "Auto") : String(format: "%.0f", fanSpeed),
                    unit: isAuto ? "RPM" : "%",
                    icon: "fan.fill",
                    color: AppColors.fan
                )
            }
        }
    }
    
    // MARK: - Charts Section
    
    private var chartsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Performance")
                        .font(.system(size: 15, weight: .semibold))
                    Text("\(updates.count) data points")
                        .font(.system(size: 11))
                        .foregroundStyle(AppColors.mutedText)
                }
                
                Spacer()
                
                Picker("Range", selection: $selectedTimeRange) {
                    ForEach(ChartTimeRange.allCases, id: \.self) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 130)
                .onChange(of: selectedTimeRange) { _, _ in selectedChartTime = nil }
            }
            
            Picker("Chart", selection: $selectedChartTab) {
                Text("Hash Rate").tag(0)
                Text("Power").tag(1)
                Text("Temp").tag(2)
            }
            .pickerStyle(.segmented)
            .onChange(of: selectedChartTab) { _, _ in selectedChartTime = nil }
            
            if hasAnyChartData || updates.count > 0 {
                ZStack(alignment: .topTrailing) {
                    Group {
                        switch selectedChartTab {
                        case 0: hashRateChart
                        case 1: powerChart
                        case 2: temperatureChart
                        default: hashRateChart
                        }
                    }
                    .frame(height: 160)
                    
                    if hasDataForSelectedRange { selectedValueBadge.padding(8) }
                    
                    if !hasDataForSelectedRange {
                        VStack(spacing: 4) {
                            Text("No data for \(selectedTimeRange.displayName.lowercased())")
                                .font(.system(size: 12))
                                .foregroundStyle(AppColors.subtleText)
                            if updates.count > 0 {
                                Text("Try a shorter time range")
                                    .font(.system(size: 11))
                                    .foregroundStyle(AppColors.mutedText)
                            }
                        }
                        .padding(8)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            } else {
                chartPlaceholder
            }
        }
        .padding(14)
        .cardStyle()
    }
    
    private var chartPlaceholder: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(AppColors.mutedText)
            
            Text("Collecting Data")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppColors.subtleText)
            
            Text("Charts will appear after data is collected")
                .font(.system(size: 12))
                .foregroundStyle(AppColors.mutedText)
                .multilineTextAlignment(.center)
            
            ProgressView().scaleEffect(0.8)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 160)
    }
    
    // MARK: - Charts
    
    private var selectedUpdate: MinerUpdate? {
        guard let time = selectedChartTime else { return nil }
        return chartUpdates.min(by: {
            abs(Date(timeIntervalSince1970: TimeInterval($0.timestamp) / 1000).timeIntervalSince(time)) <
            abs(Date(timeIntervalSince1970: TimeInterval($1.timestamp) / 1000).timeIntervalSince(time))
        })
    }
    
    @ViewBuilder
    private var selectedValueBadge: some View {
        VStack(alignment: .trailing, spacing: 2) {
            if let update = selectedUpdate {
                let time = Date(timeIntervalSince1970: TimeInterval(update.timestamp) / 1000)
                
                Group {
                    switch selectedChartTab {
                    case 0:
                        let h = formatMinerHashRate(rawRateValue: update.hashRate)
                        Text("\(h.rateString) \(h.rateSuffix)")
                    case 1:
                        Text(String(format: "%.1f W", update.power))
                    case 2:
                        Text(update.temp.map { String(format: "%.1f°C", $0) } ?? "--")
                    default:
                        Text("--")
                    }
                }
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(AppColors.accent)
                
                Text(time, format: .dateTime.hour().minute().second())
                    .font(.system(size: 10))
                    .foregroundStyle(AppColors.subtleText)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(selectedUpdate != nil ? AppColors.accent.opacity(0.1) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
    
    private var hashRateUnit: (divisor: Double, label: String) {
        guard let maxRate = chartUpdates.map({ $0.hashRate }).max(), maxRate > 0 else {
            return (1, "GH/s")
        }
        let maxRateInH = maxRate * 1_000_000_000
        if maxRateInH >= 1_000_000_000_000_000 { return (1_000_000, "PH/s") }
        if maxRateInH >= 1_000_000_000_000 { return (1_000, "TH/s") }
        if maxRateInH >= 1_000_000_000 { return (1, "GH/s") }
        if maxRateInH >= 1_000_000 { return (0.001, "MH/s") }
        return (0.000001, "KH/s")
    }
    
    private var hashRateChart: some View {
        let unit = hashRateUnit
        let domain = chartTimeDomain
        
        return Chart {
            ForEach(chartUpdates, id: \.timestamp) { update in
                let date = Date(timeIntervalSince1970: TimeInterval(update.timestamp) / 1000)
                let value = update.hashRate / unit.divisor
                
                LineMark(x: .value("Time", date), y: .value("Hash Rate", value))
                    .foregroundStyle(AppColors.chartGreen)
                    .interpolationMethod(.catmullRom)
                
                AreaMark(x: .value("Time", date), y: .value("Hash Rate", value))
                    .foregroundStyle(AppColors.chartGreen.opacity(0.08))
                    .interpolationMethod(.catmullRom)
            }
            
            if let selected = selectedUpdate {
                let date = Date(timeIntervalSince1970: TimeInterval(selected.timestamp) / 1000)
                let value = selected.hashRate / unit.divisor
                RuleMark(x: .value("Selected", date)).foregroundStyle(Color.primary.opacity(0.2)).lineStyle(StrokeStyle(lineWidth: 1))
                PointMark(x: .value("Time", date), y: .value("Hash Rate", value)).foregroundStyle(AppColors.chartGreen).symbolSize(60)
            }
        }
        .chartXScale(domain: domain)
        .chartXSelection(value: $selectedChartTime)
        .chartYAxisLabel(unit.label)
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4])).foregroundStyle(Color(.separator).opacity(0.5))
                AxisValueLabel { if let val = value.as(Double.self) { Text(String(format: "%.1f", val)).font(.system(size: 9)) } }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4])).foregroundStyle(Color(.separator).opacity(0.5))
                AxisValueLabel(format: .dateTime.hour().minute()).font(.system(size: 9))
            }
        }
    }
    
    private var powerChart: some View {
        let domain = chartTimeDomain
        
        return Chart {
            ForEach(chartUpdates, id: \.timestamp) { update in
                let date = Date(timeIntervalSince1970: TimeInterval(update.timestamp) / 1000)
                LineMark(x: .value("Time", date), y: .value("Power", update.power))
                    .foregroundStyle(AppColors.chartOrange)
                    .interpolationMethod(.catmullRom)
                AreaMark(x: .value("Time", date), y: .value("Power", update.power))
                    .foregroundStyle(AppColors.chartOrange.opacity(0.08))
                    .interpolationMethod(.catmullRom)
            }
            
            if let selected = selectedUpdate {
                let date = Date(timeIntervalSince1970: TimeInterval(selected.timestamp) / 1000)
                RuleMark(x: .value("Selected", date)).foregroundStyle(Color.primary.opacity(0.2)).lineStyle(StrokeStyle(lineWidth: 1))
                PointMark(x: .value("Time", date), y: .value("Power", selected.power)).foregroundStyle(AppColors.chartOrange).symbolSize(60)
            }
        }
        .chartXScale(domain: domain)
        .chartXSelection(value: $selectedChartTime)
        .chartYAxisLabel("W")
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4])).foregroundStyle(Color(.separator).opacity(0.5))
                AxisValueLabel { if let val = value.as(Double.self) { Text(String(format: "%.0f", val)).font(.system(size: 9)) } }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4])).foregroundStyle(Color(.separator).opacity(0.5))
                AxisValueLabel(format: .dateTime.hour().minute()).font(.system(size: 9))
            }
        }
    }
    
    private var temperatureChart: some View {
        let domain = chartTimeDomain
        
        return Chart {
            ForEach(chartUpdates, id: \.timestamp) { update in
                let date = Date(timeIntervalSince1970: TimeInterval(update.timestamp) / 1000)
                if let temp = update.temp {
                    LineMark(x: .value("Time", date), y: .value("ASIC", temp), series: .value("Type", "ASIC"))
                        .foregroundStyle(AppColors.chartOrange)
                        .interpolationMethod(.catmullRom)
                }
                if let vrTemp = update.vrTemp, vrTemp > 0 {
                    LineMark(x: .value("Time", date), y: .value("VR", vrTemp), series: .value("Type", "VR"))
                        .foregroundStyle(AppColors.chartBlue)
                        .interpolationMethod(.catmullRom)
                }
            }
            
            if let selected = selectedUpdate {
                let date = Date(timeIntervalSince1970: TimeInterval(selected.timestamp) / 1000)
                RuleMark(x: .value("Selected", date)).foregroundStyle(Color.primary.opacity(0.2)).lineStyle(StrokeStyle(lineWidth: 1))
                if let temp = selected.temp {
                    PointMark(x: .value("Time", date), y: .value("ASIC", temp)).foregroundStyle(AppColors.chartOrange).symbolSize(60)
                }
                if let vrTemp = selected.vrTemp, vrTemp > 0 {
                    PointMark(x: .value("Time", date), y: .value("VR", vrTemp)).foregroundStyle(AppColors.chartBlue).symbolSize(60)
                }
            }
        }
        .chartXScale(domain: domain)
        .chartXSelection(value: $selectedChartTime)
        .chartYAxisLabel("°C")
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4])).foregroundStyle(Color(.separator).opacity(0.5))
                AxisValueLabel { if let val = value.as(Double.self) { Text(String(format: "%.0f°", val)).font(.system(size: 9)) } }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4])).foregroundStyle(Color(.separator).opacity(0.5))
                AxisValueLabel(format: .dateTime.hour().minute()).font(.system(size: 9))
            }
        }
        .chartLegend(position: .top)
    }
    
    // MARK: - Mining Stats Card
    
    private func miningStatsCard(update: MinerUpdate) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Mining Stats")
                .font(.system(size: 15, weight: .semibold))
            
            HStack(spacing: 20) {
                ShareCounter(value: update.sharesAccepted ?? 0, label: "Accepted", color: AppColors.success)
                ShareCounter(value: update.sharesRejected ?? 0, label: "Rejected", color: (update.sharesRejected ?? 0) > 0 ? AppColors.error : AppColors.mutedText)
                Spacer()
            }
            
            Divider()
            
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Best Difficulty")
                        .font(.system(size: 11))
                        .foregroundStyle(AppColors.subtleText)
                    Text(update.bestDiff ?? "—")
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Session Best")
                        .font(.system(size: 11))
                        .foregroundStyle(AppColors.subtleText)
                    Text(update.bestSessionDiff ?? "—")
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .cardStyle()
    }
    
    // MARK: - System Info Card
    
    private func systemInfoCard(update: MinerUpdate) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("System")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppColors.subtleText)
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 8)
            
            VStack(spacing: 0) {
                InfoRow(icon: "info.circle", label: "Firmware", value: update.minerFirmwareVersion)
                Divider().padding(.leading, 44)
                InfoRow(icon: "cpu", label: "ASIC", value: update.axeOSVersion ?? "—")
                Divider().padding(.leading, 44)
                InfoRow(icon: "clock", label: "Uptime", value: formatUptime(update.uptimeSeconds ?? 0))
                Divider().padding(.leading, 44)
                InfoRow(icon: "network", label: "MAC Address", value: miner.macAddress)
                
                if let fanSpeed = update.fanspeed {
                    Divider().padding(.leading, 44)
                    InfoRow(icon: "fan", label: "Fan Duty", value: String(format: "%.0f%%", fanSpeed))
                }
                
                if let voltage = update.voltage {
                    Divider().padding(.leading, 44)
                    InfoRow(icon: "bolt", label: "Voltage", value: String(format: "%.2fV", voltage))
                }
            }
            .padding(.bottom, 4)
        }
        .cardStyle()
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
        Button {
            showRestartAlert = true
        } label: {
            HStack {
                if isRestarting { ProgressView().tint(.white) }
                else { Image(systemName: "arrow.clockwise") }
                Text(isRestarting ? "Restarting..." : "Restart Miner")
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(AppColors.warning)
        .controlSize(.large)
        .disabled(isRestarting || miner.isOffline)
        .padding(14)
        .cardStyle()
    }
    
    // MARK: - Actions
    
    private func refreshMiner() async {
        isRefreshing = true
        defer { isRefreshing = false }
        
        let client = AxeOSClient(deviceIpAddress: miner.ipAddress, urlSession: .shared)
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
        
        let client = AxeOSClient(deviceIpAddress: miner.ipAddress, urlSession: .shared)
        if case .success = await client.restartClient() {
            restartSuccess = true
        }
    }
    
    private func startAutoRefresh() {
        Task {
            await refreshMiner()
            isInitialLoad = false
        }
        
        refreshTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(chartPollingInterval), repeats: true) { _ in
            Task { await refreshMiner() }
        }
    }
    
    private func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
}

// MARK: - Supporting Views

struct StatCard: View {
    let title: String
    let value: String
    let unit: String
    let icon: String
    let color: Color
    
    @State private var isHighlighted = false
    @State private var previousValue = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(color)
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppColors.subtleText)
            }
            
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(color)
                    .contentTransition(.numericText(value: Double(value) ?? 0))
                    .animation(.spring(response: 0.4, dampingFraction: 0.75), value: value)
                
                Text(unit)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppColors.mutedText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            ZStack {
                AppColors.cardBackground
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(color.opacity(isHighlighted ? 0.1 : 0))
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(AppColors.cardBorder, lineWidth: 0.5)
        )
        .onChange(of: value) { oldValue, newValue in
            if oldValue != newValue && !previousValue.isEmpty {
                withAnimation(.easeIn(duration: 0.1)) { isHighlighted = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    withAnimation(.easeOut(duration: 0.4)) { isHighlighted = false }
                }
            }
            previousValue = newValue
        }
        .onAppear { previousValue = value }
    }
}

struct InfoRow: View {
    let icon: String
    let label: String
    let value: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(AppColors.subtleText)
                .frame(width: 22)
            
            Text(label)
                .font(.system(size: 14))
            
            Spacer()
            
            Text(value)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(AppColors.subtleText)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

struct ShareCounter: View {
    let value: Int
    let label: String
    let color: Color
    
    @State private var isHighlighted = false
    @State private var previousValue: Int = 0
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
                    .scaleEffect(isHighlighted ? 1.3 : 1.0)
                    .animation(.spring(response: 0.25, dampingFraction: 0.5), value: isHighlighted)
                
                Text("\(value)")
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.35, dampingFraction: 0.75), value: value)
            }
            
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(AppColors.subtleText)
        }
        .onChange(of: value) { oldValue, newValue in
            if oldValue != newValue && previousValue > 0 {
                withAnimation(.easeIn(duration: 0.1)) { isHighlighted = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    withAnimation(.easeOut(duration: 0.3)) { isHighlighted = false }
                }
            }
            previousValue = newValue
        }
        .onAppear { previousValue = value }
    }
}

// MARK: - Logs Sheet (Placeholder - keep existing implementation)

// The MinerLogsSheet implementation remains unchanged from the previous version
// Just importing it here for reference

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
