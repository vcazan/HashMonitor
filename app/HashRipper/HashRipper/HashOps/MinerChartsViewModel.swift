//
//  MinerChartsViewModel.swift
//  HashRipper
//
//  Created by Matt Sellars
//

import Foundation
import SwiftData
import SwiftUI
import Combine

/// Intuitive time range options for charts
enum ChartTimeRange: String, CaseIterable, Identifiable {
    case oneHour = "1h"
    case threeHours = "3h"
    case eightHours = "8h"
    case twentyFourHours = "24h"
    case threeDays = "3d"
    case sevenDays = "7d"
    case thirtyDays = "30d"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .oneHour: return "Last Hour"
        case .threeHours: return "Last 3 Hours"
        case .eightHours: return "Last 8 Hours"
        case .twentyFourHours: return "Last 24 Hours"
        case .threeDays: return "Last 3 Days"
        case .sevenDays: return "Last 7 Days"
        case .thirtyDays: return "Last 30 Days"
        }
    }
    
    var shortName: String {
        rawValue.uppercased()
    }
    
    /// Returns the time interval in seconds
    var timeInterval: TimeInterval {
        switch self {
        case .oneHour: return 3600
        case .threeHours: return 3600 * 3
        case .eightHours: return 3600 * 8
        case .twentyFourHours: return 3600 * 24
        case .threeDays: return 3600 * 24 * 3
        case .sevenDays: return 3600 * 24 * 7
        case .thirtyDays: return 3600 * 24 * 30
        }
    }
    
    /// Start date for this time range
    var startDate: Date {
        Date().addingTimeInterval(-timeInterval)
    }
    
    /// Timestamp in milliseconds for database queries
    var startTimestamp: Int64 {
        Int64(startDate.timeIntervalSince1970 * 1000)
    }
    
    /// Maximum data points to display for each time range
    /// Longer ranges need more aggressive downsampling to keep UI responsive
    var maxDataPoints: Int {
        switch self {
        case .oneHour: return 500       // ~7 seconds per point
        case .threeHours: return 600    // ~18 seconds per point
        case .eightHours: return 800    // ~36 seconds per point
        case .twentyFourHours: return 1000  // ~86 seconds per point
        case .threeDays: return 1000    // ~4 minutes per point
        case .sevenDays: return 1000    // ~10 minutes per point
        case .thirtyDays: return 1000   // ~43 minutes per point
        }
    }
}

@MainActor
class MinerChartsViewModel: ObservableObject {
    @Published var miners: [Miner] = []
    @Published var chartData: [ChartSegmentedDataEntry] = []
    @Published var chartDataBySegment: [ChartSegments: [ChartSegmentedDataEntry]] = [:]
    @Published var isLoading = false
    @Published var currentMiner: Miner?
    @Published var selectedTimeRange: ChartTimeRange = .oneHour
    @Published var totalDataPoints = 0
    @Published var isPaginating = false
    @Published var dataTimeRange: (start: Date, end: Date)?

    private var modelContext: ModelContext?
    private let initialMinerMacAddress: String?
    private var notificationSubscription: AnyCancellable?
    private var debounceTask: Task<Void, Never>?
    
    init(modelContext: ModelContext?, initialMinerMacAddress: String?) {
        self.modelContext = modelContext
        self.initialMinerMacAddress = initialMinerMacAddress
    }
    
    deinit {
        notificationSubscription?.cancel()
        debounceTask?.cancel()
    }
    
    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }
    
    private func setupNotificationSubscription() {
        notificationSubscription = NotificationCenter.default
            .publisher(for: .minerUpdateInserted)
            .compactMap { notification in
                notification.userInfo?["macAddress"] as? String
            }
            .debounce(for: .seconds(0.2), scheduler: RunLoop.main)
            .filter { [weak self] macAddress in
                self?.currentMiner?.macAddress == macAddress
            }
            .sink { [weak self] _ in
                self?.refreshChartDataWithDebounce()
            }
    }
    
    private func refreshChartDataWithDebounce() {
        // Cancel any existing debounce task
        debounceTask?.cancel()
        
        debounceTask = Task { @MainActor in
            // Wait 200ms to batch multiple rapid updates
            try? await Task.sleep(nanoseconds: 200_000_000)
            
            if !Task.isCancelled, let miner = currentMiner {
                await loadChartData(for: miner, showLoading: false)
            }
        }
    }
    
    func loadMiners() async {
        guard let modelContext = modelContext else { return }
        
        isLoading = true
        
        do {
            let descriptor = FetchDescriptor<Miner>(
                sortBy: [SortDescriptor(\Miner.hostName)]
            )
            miners = try modelContext.fetch(descriptor)
            
            // Find the initial miner by macAddress if provided
            if let initialMacAddress = initialMinerMacAddress,
               let initialMiner = miners.first(where: { $0.macAddress == initialMacAddress }) {
                currentMiner = initialMiner
                await loadChartData(for: initialMiner)
            } else if let firstMiner = miners.first {
                // Fallback to first miner if no initial miner or initial not found
                currentMiner = firstMiner
                await loadChartData(for: firstMiner)
            }
            
            // Set up notification subscription after initial load
            setupNotificationSubscription()
        } catch {
            print("Error loading miners: \(error)")
        }
        
        isLoading = false
    }
    
    func loadChartData(for miner: Miner, showLoading: Bool = true) async {
        if showLoading {
            isLoading = true
        } else {
            isPaginating = true
        }

        // Capture values on main actor
        let macAddress = miner.macAddress
        let startTimestamp = selectedTimeRange.startTimestamp
        let maxPoints = selectedTimeRange.maxDataPoints

        // Perform database operations on background thread
        let result = await Task.detached {
            // Use a background context from the shared database for better performance
            let backgroundContext = ModelContext(SharedDatabase.shared.modelContainer)

            do {
                // Fetch data within the selected time range
                let descriptor = FetchDescriptor<MinerUpdate>(
                    predicate: #Predicate<MinerUpdate> { update in
                        update.macAddress == macAddress && update.timestamp >= startTimestamp
                    },
                    sortBy: [SortDescriptor(\MinerUpdate.timestamp, order: .forward)] // Oldest first for chronological order
                )

                let updates = try backgroundContext.fetch(descriptor)
                let totalCount = updates.count
                
                // Downsample if we have too many points for smooth rendering
                let sampled: [MinerUpdate]
                if updates.count > maxPoints {
                    sampled = Self.downsample(updates, to: maxPoints)
                } else {
                    sampled = updates
                }

                let nextChartData = sampled.map { update in
                    ChartSegmentedDataEntry(
                        time: Date(milliseconds: update.timestamp),
                        values: [
                            ChartSegmentValues(primary: update.hashRate, secondary: nil),
                            ChartSegmentValues(primary: update.temp ?? 0, secondary: nil),
                            ChartSegmentValues(primary: update.vrTemp ?? 0, secondary: nil),
                            ChartSegmentValues(primary: Double(update.fanrpm ?? 0), secondary: Double(update.fanspeed ?? 0)),
                            ChartSegmentValues(primary: update.power, secondary: nil),
                            ChartSegmentValues(primary: (update.voltage ?? 0) / 1000.0, secondary: nil)
                        ]
                    )
                }
                
                // Get actual time range of data (from full dataset, not sampled)
                let firstTime = updates.first.map { Date(milliseconds: $0.timestamp) }
                let lastTime = updates.last.map { Date(milliseconds: $0.timestamp) }

                return (nextChartData, totalCount, firstTime, lastTime, nil as Error?)
            } catch {
                return ([], 0, nil as Date?, nil as Date?, error)
            }
        }.value

        // Update UI on main actor with smooth animation
        let (nextChartData, totalCount, firstTime, lastTime, error) = result

        if let error = error {
            print("Error loading chart data: \(error)")
            chartData = []
            totalDataPoints = 0
            dataTimeRange = nil
        } else {
            totalDataPoints = totalCount
            if let first = firstTime, let last = lastTime {
                dataTimeRange = (first, last)
            } else {
                dataTimeRange = nil
            }

            // Update all charts simultaneously with optimized animation
            let chartsToShow: [ChartSegments] = ChartSegments.allCases.filter({ $0 != ChartSegments.voltageRegulatorTemperature })

            withAnimation(.easeInOut(duration: 0.3)) {
                chartData = nextChartData

                // Update all segment-specific data at once
                for segment in chartsToShow {
                    chartDataBySegment[segment] = nextChartData
                }

                // For asicTemperature chart, also update VR temperature data
                chartDataBySegment[.voltageRegulatorTemperature] = nextChartData
            }
        }

        if showLoading {
            isLoading = false
        } else {
            isPaginating = false
        }
    }


    func selectMiner(_ miner: Miner) async {
        guard currentMiner?.id != miner.id else { return }

        currentMiner = miner
        await loadChartData(for: miner)

        // Update notification subscription for the new miner
        setupNotificationSubscription()
    }
    
    func nextMiner() async {
        guard let current = currentMiner,
              let currentIndex = miners.firstIndex(where: { $0.id == current.id }),
              currentIndex < miners.count - 1 else { return }

        await selectMiner(miners[currentIndex + 1])
    }

    func previousMiner() async {
        guard let current = currentMiner,
              let currentIndex = miners.firstIndex(where: { $0.id == current.id }),
              currentIndex > 0 else { return }

        await selectMiner(miners[currentIndex - 1])
    }

    // Time range selection
    func setTimeRange(_ range: ChartTimeRange) async {
        guard let miner = currentMiner else { return }
        selectedTimeRange = range
        await loadChartData(for: miner, showLoading: false)
    }

    var timeRangeInfo: String {
        if totalDataPoints == 0 {
            return "No data for \(selectedTimeRange.displayName.lowercased())"
        }
        
        guard let range = dataTimeRange else {
            return "\(totalDataPoints) data points"
        }
        
        let formatter = DateFormatter()
        let calendar = Calendar.current
        
        if calendar.isDate(range.start, inSameDayAs: range.end) {
            formatter.dateFormat = "MMM d, h:mm a"
            let endTime = DateFormatter()
            endTime.dateFormat = "h:mm a"
            return "\(formatter.string(from: range.start)) – \(endTime.string(from: range.end))"
        } else {
            formatter.dateFormat = "MMM d, h:mm a"
            return "\(formatter.string(from: range.start)) – \(formatter.string(from: range.end))"
        }
    }
    
    var dataPointsInfo: String {
        if totalDataPoints == 0 {
            return "No data"
        }
        let displayedPoints = min(totalDataPoints, selectedTimeRange.maxDataPoints)
        if totalDataPoints > selectedTimeRange.maxDataPoints {
            return "\(displayedPoints) of \(totalDataPoints) points (sampled)"
        }
        return "\(totalDataPoints) data points"
    }
    
    var isNextMinerButtonDisabled: Bool {
        guard let current = currentMiner,
              let currentIndex = miners.firstIndex(where: { $0.id == current.id }) else {
            return true
        }
        return currentIndex == miners.count - 1
    }
    
    var isPreviousMinerButtonDisabled: Bool {
        guard let current = currentMiner,
              let currentIndex = miners.firstIndex(where: { $0.id == current.id }) else {
            return true
        }
        return currentIndex == 0
    }
    
    func mostRecentUpdateTitleValue(segmentIndex: Int) -> String {
        // Use the segment-specific data if available, otherwise fall back to general chartData
        let segment = ChartSegments(rawValue: segmentIndex) ?? .hashRate
        let value = chartDataBySegment[segment]?.last?.values[segmentIndex] ?? chartData.last?.values[segmentIndex]
        switch ChartSegments(rawValue: segmentIndex) ?? .hashRate {
        case .hashRate:
            let f = formatMinerHashRate(rawRateValue: value?.primary ?? 0)
            return "\(f.rateString)\(f.rateSuffix)"
        case .voltage, .power:
            return String(format: "%.1f", value?.primary ?? 0)
        case .voltageRegulatorTemperature, .asicTemperature:
            let mf = MeasurementFormatter()
            mf.unitOptions = .providedUnit
            mf.numberFormatter.maximumFractionDigits = 1
            let temp = Measurement(value: value?.primary ?? 0, unit: UnitTemperature.celsius)
            return mf.string(from: temp)
        case .fanRPM:
            let fanRPM = Int(value?.primary ?? 0)
            let fanSpeedPct = Int(value?.secondary ?? 0)
            return "\(fanRPM) · \(fanSpeedPct)%"
        }
    }
    
    // MARK: - Downsampling
    
    /// Downsamples an array of MinerUpdate to a target count using LTTB (Largest Triangle Three Buckets) algorithm
    /// This preserves visual fidelity while dramatically reducing point count
    private nonisolated static func downsample(_ data: [MinerUpdate], to targetCount: Int) -> [MinerUpdate] {
        guard data.count > targetCount, targetCount >= 2 else { return data }
        
        var result = [MinerUpdate]()
        result.reserveCapacity(targetCount)
        
        // Always keep first point
        result.append(data[0])
        
        // Bucket size (minus first and last points)
        let bucketSize = Double(data.count - 2) / Double(targetCount - 2)
        
        var previousIndex = 0
        
        for i in 0..<(targetCount - 2) {
            // Calculate bucket range
            let bucketStart = Int(Double(i) * bucketSize) + 1
            let bucketEnd = min(Int(Double(i + 1) * bucketSize) + 1, data.count - 1)
            
            // Calculate average point for next bucket (for triangle calculation)
            let nextBucketStart = bucketEnd
            let nextBucketEnd = min(Int(Double(i + 2) * bucketSize) + 1, data.count - 1)
            
            var avgX: Double = 0
            var avgY: Double = 0
            var avgCount = 0
            
            for j in nextBucketStart..<nextBucketEnd {
                avgX += Double(data[j].timestamp)
                avgY += data[j].hashRate // Use hashRate as primary metric for downsampling
                avgCount += 1
            }
            
            if avgCount > 0 {
                avgX /= Double(avgCount)
                avgY /= Double(avgCount)
            }
            
            // Find point in current bucket with largest triangle area
            let prevX = Double(data[previousIndex].timestamp)
            let prevY = data[previousIndex].hashRate
            
            var maxArea: Double = -1
            var maxIndex = bucketStart
            
            for j in bucketStart..<bucketEnd {
                let currX = Double(data[j].timestamp)
                let currY = data[j].hashRate
                
                // Calculate triangle area using cross product
                let area = abs((prevX - avgX) * (currY - prevY) - (prevX - currX) * (avgY - prevY))
                
                if area > maxArea {
                    maxArea = area
                    maxIndex = j
                }
            }
            
            result.append(data[maxIndex])
            previousIndex = maxIndex
        }
        
        // Always keep last point
        result.append(data[data.count - 1])
        
        return result
    }
}
