//
//  MinerChartsSheet.swift
//  HashRipper
//
//  Clean charts view for a single miner
//

import SwiftUI
import SwiftData
import Charts

struct MinerChartsSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    
    let miner: Miner
    let onClose: () -> Void
    
    @StateObject private var viewModel: MinerChartsViewModel
    
    init(miner: Miner, onClose: @escaping () -> Void) {
        self.miner = miner
        self.onClose = onClose
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
                    VStack(spacing: 24) {
                        // Pagination controls
                        paginationControls
                        
                        // Charts
                        ForEach(chartsToShow, id: \.self) { segment in
                            chartCard(for: segment)
                        }
                    }
                    .padding(24)
                }
            }
        }
        .frame(width: 700, height: 700)
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            viewModel.setModelContext(modelContext)
            await viewModel.loadMiners()
        }
    }
    
    // MARK: - Header
    
    private var header: some View {
        HStack(spacing: 12) {
            Image.icon(forMinerType: miner.minerType)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 32, height: 32)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(miner.hostName)
                    .font(.system(size: 15, weight: .semibold))
                Text("Performance Charts")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .background(colorScheme == .dark ? Color(white: 0.2) : Color(white: 0.92))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
    
    // MARK: - Loading
    
    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading chart data...")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Time Range Controls
    
    private var paginationControls: some View {
        HStack(spacing: 16) {
            // Time range info
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.timeRangeInfo)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(viewModel.dataPointsInfo)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            
            Spacer()
            
            // Time range picker
            HStack(spacing: 4) {
                ForEach(ChartTimeRange.allCases) { range in
                    Button(action: {
                        Task { await viewModel.setTimeRange(range) }
                    }) {
                        Text(range.shortName)
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                viewModel.selectedTimeRange == range
                                    ? Color.blue
                                    : (colorScheme == .dark ? Color(white: 0.15) : Color(white: 0.94))
                            )
                            .foregroundStyle(viewModel.selectedTimeRange == range ? .white : .primary)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isPaginating)
                    .help(range.displayName)
                }
                
                if viewModel.isPaginating {
                    ProgressView()
                        .scaleEffect(0.6)
                        .padding(.leading, 8)
                }
            }
            .padding(4)
            .background(colorScheme == .dark ? Color(white: 0.12) : Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(color: colorScheme == .dark ? .black.opacity(0.3) : .black.opacity(0.06), radius: 2, x: 0, y: 1)
        }
    }
    
    // MARK: - Chart Card
    
    private func chartCard(for segment: ChartSegments) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: segment.iconName)
                    .font(.system(size: 14))
                    .foregroundStyle(segment.color)
                
                Text(segment.title)
                    .font(.system(size: 13, weight: .semibold))
                
                Spacer()
                
                // Current value
                Text(viewModel.mostRecentUpdateTitleValue(segmentIndex: segment.rawValue))
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(segment.color)
                
                Text(segment.symbol)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            
            // Chart
            chartContent(for: segment)
                .frame(height: 120)
        }
        .padding(16)
        .background(colorScheme == .dark ? Color(white: 0.1) : .white)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: colorScheme == .dark ? .black.opacity(0.3) : .black.opacity(0.06), radius: 2, x: 0, y: 1)
    }
    
    @ViewBuilder
    private func chartContent(for segment: ChartSegments) -> some View {
        Chart {
            ForEach(viewModel.chartDataBySegment[segment] ?? [], id: \.time) { entry in
                if segment == .asicTemperature {
                    // ASIC Temp
                    LineMark(
                        x: .value("Time", entry.time),
                        y: .value("ASIC", entry.values[ChartSegments.asicTemperature.rawValue].primary),
                        series: .value("Type", "ASIC")
                    )
                    .foregroundStyle(ChartSegments.asicTemperature.color)
                    .interpolationMethod(.catmullRom)
                    
                    // VR Temp
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
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color(nsColor: .separatorColor).opacity(0.5))
                AxisValueLabel(format: .dateTime.hour().minute())
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color(nsColor: .separatorColor).opacity(0.5))
                AxisValueLabel()
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

