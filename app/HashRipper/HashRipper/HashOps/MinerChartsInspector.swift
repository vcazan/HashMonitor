//
//  MinerChartsInspector.swift
//  HashRipper
//
//  Charts view for inspector/drawer presentation
//

import SwiftUI
import SwiftData
import Charts

struct MinerChartsInspector: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    
    let miner: Miner
    @Binding var isPresented: Bool
    
    @StateObject private var viewModel: MinerChartsViewModel
    
    // Track selected time per chart segment
    @State private var selectedTime: [ChartSegments: Date] = [:]
    
    init(miner: Miner, isPresented: Binding<Bool>) {
        self.miner = miner
        self._isPresented = isPresented
        self._viewModel = StateObject(wrappedValue: MinerChartsViewModel(
            modelContext: nil,
            initialMinerMacAddress: miner.macAddress
        ))
    }
    
    private var chartsToShow: [ChartSegments] {
        ChartSegments.allCases.filter { $0 != .voltageRegulatorTemperature }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
            
            Divider()
            
            // Content
            if viewModel.isLoading {
                loadingView
            } else {
                ScrollView {
                    VStack(spacing: 20) {
                        // Pagination controls
                        paginationControls
                            .padding(.horizontal, 16)
                        
                        // Charts
                        ForEach(chartsToShow, id: \.self) { segment in
                            chartCard(for: segment)
                        }
                        .padding(.horizontal, 16)
                    }
                    .padding(.vertical, 16)
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            viewModel.setModelContext(modelContext)
            await viewModel.loadMiners()
        }
        .onChange(of: miner.macAddress) { _, _ in
            Task {
                await viewModel.loadMiners()
            }
        }
    }
    
    // MARK: - Header
    
    private var header: some View {
        HStack(spacing: 10) {
            Image.icon(forMinerType: miner.minerType)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 28, height: 28)
            
            VStack(alignment: .leading, spacing: 1) {
                Text(miner.hostName)
                    .font(.system(size: 13, weight: .semibold))
                Text("Performance Charts")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Button(action: { isPresented = false }) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .background(colorScheme == .dark ? Color(white: 0.2) : Color(white: 0.92))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Close")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minHeight: 64)
    }
    
    // MARK: - Loading
    
    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading chart data...")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Time Range Controls
    
    private var timeRangeControls: some View {
        VStack(spacing: 8) {
            // Time range info - only this part updates with new data
            VStack(spacing: 2) {
                Text(viewModel.timeRangeInfo)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                Text(viewModel.dataPointsInfo)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .contentTransition(.numericText())
            }
            .animation(.easeInOut(duration: 0.2), value: viewModel.totalDataPoints)
            
            // Time range picker - stable buttons that don't flash
            TimeRangeButtonsView(
                selectedRange: viewModel.selectedTimeRange,
                isPaginating: viewModel.isPaginating,
                colorScheme: colorScheme,
                onSelect: { range in
                    Task { await viewModel.setTimeRange(range) }
                }
            )
        }
    }
    
    // Keep old name for backward compatibility
    private var paginationControls: some View {
        timeRangeControls
    }
    
    // MARK: - Chart Card
    
    private func chartCard(for segment: ChartSegments) -> some View {
        let data = viewModel.chartDataBySegment[segment] ?? []
        let selectedDate = selectedTime[segment]
        let selectedEntry = selectedDate.flatMap { date in findClosestEntry(to: date, in: data) }
        let hasSelection = selectedEntry != nil
        
        return VStack(alignment: .leading, spacing: 10) {
            // Header - consistent layout whether selected or not
            HStack(spacing: 6) {
                Image(systemName: segment.iconName)
                    .font(.system(size: 12))
                    .foregroundStyle(segment.color)
                
                Text(segment.title)
                    .font(.system(size: 12, weight: .semibold))
                
                Spacer()
                
                // Fixed-size container to prevent layout shift
                chartValueBadge(segment: segment, selectedEntry: selectedEntry, hasSelection: hasSelection)
            }
            
            // Chart with interactive selection
            InteractiveChartView(
                segment: segment,
                data: data,
                selectedTime: Binding(
                    get: { selectedTime[segment] },
                    set: { selectedTime[segment] = $0 }
                ),
                colorScheme: colorScheme,
                strideMinutes: strideMinutes
            )
            .frame(height: 100)
        }
        .padding(14)
        .background(colorScheme == .dark ? Color(white: 0.1) : .white)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: colorScheme == .dark ? .black.opacity(0.3) : .black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    
    @ViewBuilder
    private func chartValueBadge(segment: ChartSegments, selectedEntry: ChartSegmentedDataEntry?, hasSelection: Bool) -> some View {
        // Use ZStack with fixed frame to prevent layout shifts
        ZStack(alignment: .trailing) {
            // Invisible placeholder to reserve max space
            VStack(alignment: .trailing, spacing: 1) {
                Text("00.0°C / 00.0°C")  // Longest possible value
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.clear)
                Text("00:00:00 AM")
                    .font(.system(size: 9))
                    .foregroundStyle(.clear)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            
            // Actual content
            VStack(alignment: .trailing, spacing: 1) {
                if let entry = selectedEntry {
                    Text(formatValue(entry: entry, segment: segment))
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(segment.color)
                    Text(entry.time, format: .dateTime.hour().minute().second())
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                } else {
                    Text(viewModel.mostRecentUpdateTitleValue(segmentIndex: segment.rawValue))
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(segment.color)
                    Text(segment.symbol)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(hasSelection ? segment.color.opacity(0.15) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }
    
    private func formatValue(entry: ChartSegmentedDataEntry, segment: ChartSegments) -> String {
        let value = entry.values[segment.rawValue].primary
        switch segment {
        case .hashRate:
            let f = formatMinerHashRate(rawRateValue: value)
            return "\(f.rateString)\(f.rateSuffix)"
        case .voltage, .power:
            return String(format: "%.1f %@", value, segment.symbol)
        case .voltageRegulatorTemperature, .asicTemperature:
            // For temp chart, show both ASIC and VR temps
            let asicTemp = entry.values[ChartSegments.asicTemperature.rawValue].primary
            let vrTemp = entry.values[ChartSegments.voltageRegulatorTemperature.rawValue].primary
            return String(format: "%.1f°C / %.1f°C", asicTemp, vrTemp)
        case .fanRPM:
            let fanRPM = Int(value)
            let fanSpeedPct = Int(entry.values[segment.rawValue].secondary ?? 0)
            return "\(fanRPM) RPM · \(fanSpeedPct)%"
        }
    }
    
    private func findClosestEntry(to date: Date, in data: [ChartSegmentedDataEntry]) -> ChartSegmentedDataEntry? {
        guard !data.isEmpty else { return nil }
        return data.min(by: { abs($0.time.timeIntervalSince(date)) < abs($1.time.timeIntervalSince(date)) })
    }
    
    /// Calculate appropriate stride interval based on time range
    private func strideMinutes(from start: Date, to end: Date) -> Int {
        let minutes = Int(end.timeIntervalSince(start) / 60)
        
        // Target 4-5 axis labels
        switch minutes {
        case 0..<30:
            return 5          // Every 5 minutes for < 30 min range
        case 30..<60:
            return 10         // Every 10 minutes for 30-60 min range
        case 60..<180:
            return 30         // Every 30 minutes for 1-3 hour range
        case 180..<360:
            return 60         // Every hour for 3-6 hour range
        case 360..<720:
            return 120        // Every 2 hours for 6-12 hour range
        default:
            return 180        // Every 3 hours for > 12 hours
        }
    }
}

// MARK: - Interactive Chart View

private struct InteractiveChartView: View {
    let segment: ChartSegments
    let data: [ChartSegmentedDataEntry]
    @Binding var selectedTime: Date?
    let colorScheme: ColorScheme
    let strideMinutes: (Date, Date) -> Int
    
    private var startTime: Date { data.first?.time ?? Date() }
    private var endTime: Date { data.last?.time ?? Date() }
    
    private var selectedEntry: ChartSegmentedDataEntry? {
        guard let time = selectedTime else { return nil }
        return data.min(by: { abs($0.time.timeIntervalSince(time)) < abs($1.time.timeIntervalSince(time)) })
    }
    
    var body: some View {
        Chart {
            ForEach(data, id: \.time) { entry in
                if segment == .asicTemperature {
                    LineMark(
                        x: .value("Time", entry.time),
                        y: .value("ASIC", entry.values[ChartSegments.asicTemperature.rawValue].primary),
                        series: .value("Type", "ASIC")
                    )
                    .foregroundStyle(ChartSegments.asicTemperature.color)
                    .interpolationMethod(.catmullRom)
                    
                    LineMark(
                        x: .value("Time", entry.time),
                        y: .value("VR", entry.values[ChartSegments.voltageRegulatorTemperature.rawValue].primary),
                        series: .value("Type", "VR")
                    )
                    .foregroundStyle(ChartSegments.voltageRegulatorTemperature.color)
                    .interpolationMethod(.catmullRom)
                } else {
                    LineMark(
                        x: .value("Time", entry.time),
                        y: .value(segment.title, entry.values[segment.rawValue].primary)
                    )
                    .foregroundStyle(segment.color)
                    .interpolationMethod(.catmullRom)
                }
            }
            
            // Crosshair rule mark when a point is selected
            if let entry = selectedEntry {
                RuleMark(x: .value("Selected", entry.time))
                    .foregroundStyle(Color.primary.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                
                // Point markers
                if segment == .asicTemperature {
                    PointMark(
                        x: .value("Time", entry.time),
                        y: .value("ASIC", entry.values[ChartSegments.asicTemperature.rawValue].primary)
                    )
                    .foregroundStyle(ChartSegments.asicTemperature.color)
                    .symbolSize(60)
                    
                    PointMark(
                        x: .value("Time", entry.time),
                        y: .value("VR", entry.values[ChartSegments.voltageRegulatorTemperature.rawValue].primary)
                    )
                    .foregroundStyle(ChartSegments.voltageRegulatorTemperature.color)
                    .symbolSize(60)
                } else {
                    PointMark(
                        x: .value("Time", entry.time),
                        y: .value(segment.title, entry.values[segment.rawValue].primary)
                    )
                    .foregroundStyle(segment.color)
                    .symbolSize(60)
                }
            }
        }
        .chartXSelection(value: $selectedTime)
        .chartXScale(domain: startTime...endTime)
        .chartXAxis {
            AxisMarks(values: .stride(by: .minute, count: strideMinutes(startTime, endTime))) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color(nsColor: .separatorColor).opacity(0.5))
                AxisValueLabel(format: .dateTime.hour().minute())
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color(nsColor: .separatorColor).opacity(0.5))
                AxisValueLabel()
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Stable Time Range Buttons

/// Separate view for time range buttons to prevent unnecessary re-renders
/// when chart data updates (which would cause button flashing)
private struct TimeRangeButtonsView: View {
    let selectedRange: ChartTimeRange
    let isPaginating: Bool
    let colorScheme: ColorScheme
    let onSelect: (ChartTimeRange) -> Void
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(ChartTimeRange.allCases) { range in
                Button(action: { onSelect(range) }) {
                    Text(range.shortName)
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            selectedRange == range
                                ? Color.blue
                                : (colorScheme == .dark ? Color(white: 0.15) : Color(white: 0.94))
                        )
                        .foregroundStyle(selectedRange == range ? .white : .primary)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        .contentShape(RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                .disabled(isPaginating)
                .help(range.displayName)
                .id(range) // Stable identity prevents re-creation
            }
        }
        .animation(.easeInOut(duration: 0.15), value: selectedRange) // Only animate selection changes
    }
}