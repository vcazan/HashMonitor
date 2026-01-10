//
//  MiningDashboardView.swift
//  HashRipper
//
//  Dashboard overview of all mining operations
//

import SwiftUI
import SwiftData

struct MiningDashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: \Miner.hostName) private var miners: [Miner]
    
    @Binding var selectedMiner: Miner?
    @State private var minerUpdates: [String: MinerUpdate] = [:] // macAddress -> latest update
    
    private var activeMiners: [Miner] {
        miners.filter { !$0.isOffline }
    }
    
    private var offlineMiners: [Miner] {
        miners.filter { $0.isOffline }
    }
    
    private func getLatestUpdate(for miner: Miner) -> MinerUpdate? {
        return minerUpdates[miner.macAddress]
    }
    
    private func loadMinerUpdates() {
        var updates: [String: MinerUpdate] = [:]
        for miner in miners {
            let macAddress = miner.macAddress
            var descriptor = FetchDescriptor<MinerUpdate>(
                predicate: #Predicate<MinerUpdate> { $0.macAddress == macAddress },
                sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
            )
            descriptor.fetchLimit = 1
            if let update = try? modelContext.fetch(descriptor).first {
                updates[macAddress] = update
            }
        }
        minerUpdates = updates
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Summary header
                summaryHeader
                
                // Active miners grid
                if !activeMiners.isEmpty {
                    minerSection(title: "Active Miners", miners: activeMiners, isActive: true)
                }
                
                // Offline miners (collapsed style)
                if !offlineMiners.isEmpty {
                    minerSection(title: "Offline Miners", miners: offlineMiners, isActive: false)
                }
                
                // Empty state
                if miners.isEmpty {
                    emptyState
                }
            }
            .padding(24)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            loadMinerUpdates()
        }
        .onReceive(NotificationCenter.default.publisher(for: .minerUpdateInserted)) { _ in
            loadMinerUpdates()
        }
    }
    
    // MARK: - Summary Header
    
    private var summaryHeader: some View {
        VStack(spacing: 20) {
            // Title row
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Dashboard")
                        .font(.system(size: 22, weight: .semibold))
                    Text("Mining operations overview")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // Status badge
                HStack(spacing: 6) {
                    Circle()
                        .fill(activeMiners.isEmpty ? Color.orange : Color.green)
                        .frame(width: 7, height: 7)
                    Text("\(activeMiners.count)/\(miners.count) online")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(colorScheme == .dark ? Color(white: 0.12) : Color(white: 0.94))
                .clipShape(Capsule())
            }
            
            // Primary metrics row
            HStack(spacing: 0) {
                // Hash Rate - primary metric
                VStack(alignment: .leading, spacing: 4) {
                    Text("HASH RATE")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .tracking(0.3)
                    
                    HStack(alignment: .lastTextBaseline, spacing: 4) {
                        Text(formattedTotalHashRate.value)
                            .font(.system(size: 32, weight: .semibold, design: .rounded))
                        Text(formattedTotalHashRate.unit)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                // Divider
                Rectangle()
                    .fill(colorScheme == .dark ? Color(white: 0.2) : Color(white: 0.85))
                    .frame(width: 1, height: 40)
                    .padding(.horizontal, 20)
                
                // Power
                VStack(alignment: .leading, spacing: 4) {
                    Text("POWER")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .tracking(0.3)
                    
                    HStack(alignment: .lastTextBaseline, spacing: 4) {
                        Text(formattedTotalPower.value)
                            .font(.system(size: 32, weight: .semibold, design: .rounded))
                        Text(formattedTotalPower.unit)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                // Divider
                Rectangle()
                    .fill(colorScheme == .dark ? Color(white: 0.2) : Color(white: 0.85))
                    .frame(width: 1, height: 40)
                    .padding(.horizontal, 20)
                
                // Efficiency
                VStack(alignment: .leading, spacing: 4) {
                    Text("EFFICIENCY")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .tracking(0.3)
                    
                    HStack(alignment: .lastTextBaseline, spacing: 4) {
                        Text(formattedEfficiency)
                            .font(.system(size: 32, weight: .semibold, design: .rounded))
                        Text("J/TH")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            // Secondary metrics
            HStack(spacing: 24) {
                SecondaryMetric(label: "Avg Temp", value: String(format: "%.1f°", averageTemperature))
                SecondaryMetric(label: "Shares", value: formatShareCount(totalAcceptedShares))
                SecondaryMetric(label: "Best Diff", value: highestBestDifficulty)
                SecondaryMetric(label: "Session", value: highestSessionDifficulty)
            }
        }
        .padding(24)
        .background(colorScheme == .dark ? Color(white: 0.06) : .white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(colorScheme == .dark ? Color(white: 0.12) : Color(white: 0.9), lineWidth: 1)
        )
    }
    
    // MARK: - Miner Section
    
    private func minerSection(title: String, miners: [Miner], isActive: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tertiary)
                .tracking(0.5)
            
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 16),
                GridItem(.flexible(), spacing: 16),
                GridItem(.flexible(), spacing: 16)
            ], spacing: 16) {
                ForEach(miners) { miner in
                    MinerTileView(miner: miner, latestUpdate: getLatestUpdate(for: miner), isActive: isActive)
                        .onTapGesture {
                            selectedMiner = miner
                        }
                }
            }
        }
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "cube.transparent")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            
            Text("No Miners Found")
                .font(.title2.bold())
            
            Text("Scan your network to discover miners or add one manually")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(60)
        .background(colorScheme == .dark ? Color(white: 0.08) : .white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    // MARK: - Computed Properties
    
    private var formattedTotalHashRate: (value: String, unit: String) {
        var total: Double = 0
        for miner in activeMiners {
            if let update = getLatestUpdate(for: miner) {
                total += update.hashRate
            }
        }
        let formatted = formatMinerHashRate(rawRateValue: total)
        return (formatted.rateString, formatted.rateSuffix)
    }
    
    private var formattedTotalPower: (value: String, unit: String) {
        var total: Double = 0
        for miner in activeMiners {
            if let update = getLatestUpdate(for: miner) {
                total += update.power
            }
        }
        if total >= 1000 {
            return (String(format: "%.2f", total / 1000), "kW")
        }
        return (String(format: "%.0f", total), "W")
    }
    
    private var averageTemperature: Double {
        var temps: [Double] = []
        for miner in activeMiners {
            if let update = getLatestUpdate(for: miner),
               let temp = update.temp {
                temps.append(temp)
            }
        }
        guard !temps.isEmpty else { return 0 }
        return temps.reduce(0, +) / Double(temps.count)
    }
    
    private var temperatureColor: Color {
        if averageTemperature >= 70 { return .red }
        if averageTemperature >= 55 { return .orange }
        return .green
    }
    
    private var totalAcceptedShares: Int {
        var total = 0
        for miner in activeMiners {
            if let update = getLatestUpdate(for: miner) {
                total += update.sharesAccepted ?? 0
            }
        }
        return total
    }
    
    private var highestBestDifficulty: String {
        var highest: (value: Double, display: String) = (0, "—")
        for miner in activeMiners {
            if let update = getLatestUpdate(for: miner),
               let bestDiff = update.bestDiff,
               !bestDiff.isEmpty && bestDiff != "N/A" {
                let value = DifficultyParser.parseDifficultyValue(bestDiff)
                if value > highest.value {
                    highest = (value, bestDiff)
                }
            }
        }
        return highest.display
    }
    
    private var highestSessionDifficulty: String {
        var highest: (value: Double, display: String) = (0, "—")
        for miner in activeMiners {
            if let update = getLatestUpdate(for: miner),
               let sessionDiff = update.bestSessionDiff,
               !sessionDiff.isEmpty && sessionDiff != "N/A" {
                let value = DifficultyParser.parseDifficultyValue(sessionDiff)
                if value > highest.value {
                    highest = (value, sessionDiff)
                }
            }
        }
        return highest.display
    }
    
    private var formattedEfficiency: String {
        var totalPower: Double = 0
        var totalHashRate: Double = 0
        for miner in activeMiners {
            if let update = getLatestUpdate(for: miner) {
                totalPower += update.power
                totalHashRate += update.hashRate
            }
        }
        // hashRate is in GH/s, convert to TH/s (divide by 1000)
        let thPerSecond = totalHashRate / 1000.0
        guard thPerSecond > 0 else { return "—" }
        let efficiency = totalPower / thPerSecond
        return String(format: "%.1f", efficiency)
    }
    
    private func formatShareCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }
}

// MARK: - Secondary Metric

private struct SecondaryMetric: View {
    let label: String
    let value: String
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(colorScheme == .dark ? Color(white: 0.08) : Color(white: 0.96))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Miner Tile View

private struct MinerTileView: View {
    let miner: Miner
    let latestUpdate: MinerUpdate?
    let isActive: Bool
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack(spacing: 10) {
                Image.icon(forMinerType: miner.minerType)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 32, height: 32)
                    .opacity(isActive ? 1 : 0.4)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(miner.hostName)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    
                    HStack(spacing: 4) {
                        Circle()
                            .fill(isActive ? Color.green : Color.red.opacity(0.6))
                            .frame(width: 5, height: 5)
                        Text(isActive ? "Online" : "Offline")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }
                
                Spacer()
                
                // Hash rate as primary metric
                if isActive, let update = latestUpdate {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(formatHashRate(update.hashRate))
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                        Text(String(format: "%.0fW", update.power))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            if isActive, let update = latestUpdate {
                // Compact stats row
                HStack(spacing: 0) {
                    MinerTileStat(label: "Temp", value: update.temp.map { String(format: "%.0f°", $0) } ?? "—")
                    MinerTileStat(label: "Shares", value: formatShares(update.sharesAccepted ?? 0))
                    MinerTileStat(label: "Best", value: update.bestDiff ?? "—")
                    MinerTileStat(label: "Session", value: update.bestSessionDiff ?? "—")
                }
            } else if !isActive {
                HStack(spacing: 6) {
                    Image(systemName: "wifi.slash")
                        .font(.system(size: 10))
                    Text("Unable to connect")
                        .font(.system(size: 10))
                }
                .foregroundStyle(.tertiary)
                .padding(.top, 2)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colorScheme == .dark ? Color(white: 0.06) : .white)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(colorScheme == .dark ? Color(white: 0.12) : Color(white: 0.9), lineWidth: 1)
        )
        .opacity(isActive ? 1 : 0.6)
    }
    
    private func formatHashRate(_ rate: Double) -> String {
        let formatted = formatMinerHashRate(rawRateValue: rate)
        return "\(formatted.rateString)\(formatted.rateSuffix)"
    }
    
    private func formatShares(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }
}

// MARK: - Miner Tile Stat

private struct MinerTileStat: View {
    let label: String
    let value: String
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(colorScheme == .dark ? Color(white: 0.08) : Color(white: 0.96))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}
