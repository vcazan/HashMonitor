//
//  MinerSegmentedChartsView.swift
//  HashRipper
//
//  Created by Matt Sellars
//

import Charts
import Foundation
import SwiftData
import SwiftUI
import AppKit

let kDataPointCount = 50

enum ChartSegments: Int, CaseIterable, Hashable  {
    case hashRate = 0
    case asicTemperature = 1
    case voltageRegulatorTemperature = 2
    case fanRPM = 3
    case power = 4
    case voltage = 5

    var tabName: String {
        switch self {
        case .hashRate:
            return "Hash Rate"
        case .asicTemperature:
            return "Temps"
        case .voltageRegulatorTemperature:
            return "VR Temp"
        case .fanRPM:
            return "Fan RPM"
        case .power:
            return "Power"
        case .voltage:
            return "Voltage"
        }
    }

    var title: String {
        switch self {
        case .hashRate:
            return "Hash Rate"
        case .asicTemperature:
            return "Asic Temp"
        case .voltageRegulatorTemperature:
            return "VR Temp"
        case .fanRPM:
            return "Fan RPM"
        case .power:
            return "Power"
        case .voltage:
            return "Voltage"
        }
    }

    var symbol: String {
        switch self {
        case .hashRate:
            return "H/s"
        case .asicTemperature:
            return "°C"
        case .voltageRegulatorTemperature:
            return "°C"
        case .fanRPM:
            return "RPM"
        case .power:
            return "W"
        default:
            return "V"
        }
    }

    var color: Color {
        switch self {
        case .hashRate:
            return .mint
        case .asicTemperature:
            return .orange
        case .voltageRegulatorTemperature:
            return .red
        case .fanRPM:
            return .cyan
        case .power:
            return .yellow
        default:
            return .pink
        }
    }

    var iconName: String {
        switch self {
        case .hashRate:
            return "gauge.with.dots.needle.67percent"
        case .asicTemperature:
            return "thermometer.variable"
        case .voltageRegulatorTemperature:
            return "thermometer.variable"
        case .fanRPM:
            return "fan.desk"
        case .voltage, .power:
            return "bolt"
        }
    }

    var iconRotates: Bool {
        switch self {
        case .fanRPM:
            return true
        default:
            return false
        }
    }
}

struct MinerSegmentedUpdateChartsView: View {
    @Environment(\.minerClientManager) var minerClientManager
    @Environment(\.modelContext) private var modelContext
    
    @StateObject private var viewModel: MinerChartsViewModel
    let miner: Miner?
    var onClose: () -> Void
    
    init(miner: Miner?, onClose: @escaping () -> Void) {
        self.miner = miner
        self.onClose = onClose
        self._viewModel = StateObject(wrappedValue: MinerChartsViewModel(modelContext: nil, initialMinerMacAddress: miner?.macAddress))
    }
    
    var currentMiner: Miner? {
        viewModel.currentMiner ?? miner
    }

    @ViewBuilder
    func chartView(for segment: ChartSegments) -> some View {
        let data = viewModel.chartDataBySegment[segment] ?? []
        let startTime = data.first?.time ?? Date()
        let endTime = data.last?.time ?? Date()
        
        VStack(alignment: .leading, spacing: 16) {
            // Title section
            VStack(alignment: .leading) {
                if segment == .asicTemperature {
                    TitleValueView(
                        segment: ChartSegments.asicTemperature,
                        value: viewModel.mostRecentUpdateTitleValue(segmentIndex: ChartSegments.asicTemperature.rawValue)
                    )
                    TitleValueView(
                        segment: ChartSegments.voltageRegulatorTemperature,
                        value: viewModel.mostRecentUpdateTitleValue(segmentIndex: ChartSegments.voltageRegulatorTemperature.rawValue)
                    )
                } else {
                    TitleValueView(
                        segment: segment,
                        value: viewModel.mostRecentUpdateTitleValue(segmentIndex: segment.rawValue)
                    )
                }
            }
            
            // Chart
            Chart {
                ForEach(data, id: \.time) { entry in
                    if segment == .asicTemperature {
                        // ASIC Temp line (orange)
                        LineMark(
                            x: .value("Time", entry.time),
                            y: .value("ASIC Temp", entry.values[ChartSegments.asicTemperature.rawValue].primary),
                            series: .value("asic", "A")
                        )
                        .foregroundStyle(ChartSegments.asicTemperature.color)
                        .interpolationMethod(.catmullRom)

                        // VR Temp line (red)
                        LineMark(
                            x: .value("Time", entry.time),
                            y: .value("VR Temp", entry.values[ChartSegments.voltageRegulatorTemperature.rawValue].primary),
                            series: .value("vr", "B")
                        )
                        .foregroundStyle(ChartSegments.voltageRegulatorTemperature.color)
                        .interpolationMethod(.catmullRom)
                    } else {
                        // Default single-line chart
                        LineMark(
                            x: .value("Time", entry.time),
                            y: .value(segment.title, entry.values[segment.rawValue].primary)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(segment.color)
                    }
                }
            }
            .chartXScale(domain: startTime...endTime)
            .chartYAxisLabel { Text(segment.symbol).font(.caption) }
            .chartXAxis {
                AxisMarks(values: .stride(by: .minute, count: strideMinutes(from: startTime, to: endTime))) { value in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.hour().minute())
                        .font(.caption2)
                }
            }
            .chartYAxis {
                AxisMarks(values: .automatic(roundLowerBound: true))
            }
            .frame(height: 200)
            .foregroundStyle(segment.color)
        }
        .padding(.horizontal)
    }
    
    /// Calculate appropriate stride interval based on time range
    private func strideMinutes(from start: Date, to end: Date) -> Int {
        let minutes = Int(end.timeIntervalSince(start) / 60)
        
        // Target 4-6 axis labels
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
    
    var chartsToShow: [ChartSegments] {
        ChartSegments.allCases.filter({ $0 != ChartSegments.voltageRegulatorTemperature })
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header section
            VStack(spacing: 16) {
                HStack {
                    Button(action: {
                        Task { await viewModel.previousMiner() }
                    }) {
                        Image(systemName: "chevron.left")
                    }
                    .disabled(viewModel.isPreviousMinerButtonDisabled)

                    Spacer()

                    Button(action: {
                        Task { await viewModel.nextMiner() }
                    }) {
                        Image(systemName: "chevron.right")
                    }
                    .disabled(viewModel.isNextMinerButtonDisabled)
                }.frame(width: 100)
            }
            .padding(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 8))
            
            Divider()
            
            // Content section
            ScrollView {
                VStack(spacing: 0) {
                    // Always show miner summary - not dependent on chart loading
                    if let currentMiner = currentMiner {
                        MinerHashOpsSummaryView(miner: currentMiner)
                    }

                    // Show loading state only for initial load, pagination shows different indicator
                    if viewModel.isLoading {
                        VStack(spacing: 16) {
                            ProgressView("Loading chart data...")
                                .progressViewStyle(CircularProgressViewStyle())

                            Text("Miner information shown above")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    } else {
                        // Time range controls
                        VStack(spacing: 8) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(viewModel.timeRangeInfo)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .contentTransition(.numericText())
                                    Text(viewModel.dataPointsInfo)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary.opacity(0.7))
                                        .contentTransition(.numericText())
                                }
                                .animation(.easeInOut(duration: 0.2), value: viewModel.totalDataPoints)

                                if viewModel.isPaginating {
                                    ProgressView()
                                        .scaleEffect(0.6)
                                        .controlSize(.mini)
                                }
                                
                                Spacer()
                            }

                            // Time range picker - stable buttons
                            SegmentedTimeRangeButtonsView(
                                selectedRange: viewModel.selectedTimeRange,
                                isPaginating: viewModel.isPaginating,
                                onSelect: { range in
                                    Task { await viewModel.setTimeRange(range) }
                                }
                            )
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)

                        // Charts section
                        LazyVStack(spacing: 32) {
                            ForEach(chartsToShow, id: \.self) { segment in
                                chartView(for: segment)
                            }
                        }
                        .padding(.vertical, 16)
                    }
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            GeometryReader { geometry in
                Button(action: onClose) {
                    Image(systemName: "xmark")
                }.position(x: geometry.size.width - 24, y: 18)
            }
        }
        .task {
            viewModel.setModelContext(modelContext)
            await viewModel.loadMiners()
        }
    }

}

struct ChartSegmentedDataEntry: Hashable {
    let time: Date

    // Index aligns with ChartSegments
    let values: [ChartSegmentValues]
}

struct ChartSegmentValues: Hashable {
    let primary: Double
    let secondary: Double?
}

struct TitleValueView: View {
    var segment: ChartSegments
    var value: String

    var body: some View {
        HStack {
            if segment.iconRotates {
                Image(systemName: segment.iconName)
                    .font(.title3)
                    .symbolEffect(.rotate)
                    .foregroundStyle(segment.color)
            } else {
                Image(systemName: segment.iconName)
                    .font(.title3)
                    .foregroundStyle(segment.color)
            }
            Text("\(segment.title) · \(value)")
                .font(.headline)
        }
    }
}

// MARK: - Stable Time Range Buttons

/// Separate view for time range buttons to prevent unnecessary re-renders
private struct SegmentedTimeRangeButtonsView: View {
    let selectedRange: ChartTimeRange
    let isPaginating: Bool
    let onSelect: (ChartTimeRange) -> Void
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(ChartTimeRange.allCases) { range in
                Button(action: { onSelect(range) }) {
                    Text(range.shortName)
                        .font(.caption2.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .tint(selectedRange == range ? .blue : .secondary)
                .controlSize(.small)
                .disabled(isPaginating)
                .help(range.displayName)
                .id(range)
            }
        }
        .transaction { $0.animation = nil } // Disable inherited animations
        .animation(.easeInOut(duration: 0.15), value: selectedRange)
    }
}
