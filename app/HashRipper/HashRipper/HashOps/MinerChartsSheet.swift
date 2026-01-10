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
    
    // MARK: - Pagination
    
    private var timeRangeText: String {
        // Get the time range from chart data
        guard let hashRateData = viewModel.chartDataBySegment[.hashRate],
              let firstEntry = hashRateData.first,
              let lastEntry = hashRateData.last else {
            return "No data"
        }
        
        let formatter = DateFormatter()
        let calendar = Calendar.current
        
        // Check if same day
        if calendar.isDate(firstEntry.time, inSameDayAs: lastEntry.time) {
            formatter.dateFormat = "MMM d, h:mm a"
            let startTime = DateFormatter()
            startTime.dateFormat = "h:mm a"
            let endTime = DateFormatter()
            endTime.dateFormat = "h:mm a"
            return "\(formatter.string(from: firstEntry.time)) – \(endTime.string(from: lastEntry.time))"
        } else {
            formatter.dateFormat = "MMM d, h:mm a"
            return "\(formatter.string(from: firstEntry.time)) – \(formatter.string(from: lastEntry.time))"
        }
    }
    
    private var paginationControls: some View {
        HStack(spacing: 16) {
            Text(timeRangeText)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            
            Spacer()
            
            HStack(spacing: 8) {
                Button(action: { Task { await viewModel.goToOlderData() } }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Older")
                            .font(.system(size: 12, weight: .medium))
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(viewModel.canGoToOlderData ? .primary : .secondary)
                .disabled(!viewModel.canGoToOlderData || viewModel.isPaginating)
                
                Divider()
                    .frame(height: 14)
                
                Button(action: { Task { await viewModel.goToMostRecentData() } }) {
                    Text("Latest")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(viewModel.canGoToNewerData ? .blue : .secondary)
                .disabled(!viewModel.canGoToNewerData || viewModel.isPaginating)
                
                Divider()
                    .frame(height: 14)
                
                Button(action: { Task { await viewModel.goToNewerData() } }) {
                    HStack(spacing: 4) {
                        Text("Newer")
                            .font(.system(size: 12, weight: .medium))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(viewModel.canGoToNewerData ? .primary : .secondary)
                .disabled(!viewModel.canGoToNewerData || viewModel.isPaginating)
                
                if viewModel.isPaginating {
                    ProgressView()
                        .scaleEffect(0.6)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(colorScheme == .dark ? Color(white: 0.12) : Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 6))
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

