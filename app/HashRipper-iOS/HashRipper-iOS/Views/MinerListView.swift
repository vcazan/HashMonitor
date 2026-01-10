//
//  MinerListView.swift
//  HashRipper-iOS
//
//  List of all miners with pull-to-refresh
//

import SwiftUI
import SwiftData
import HashRipperKit
import AxeOSClient

enum MinerSortOption: String, CaseIterable {
    case name = "Name"
    case hashRate = "Hash Rate"
    case temperature = "Temperature"
    case power = "Power"
    
    var icon: String {
        switch self {
        case .name: return "textformat"
        case .hashRate: return "bolt.fill"
        case .temperature: return "thermometer.medium"
        case .power: return "bolt.fill"
        }
    }
}

struct MinerListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Miner.hostName) private var miners: [Miner]
    @Query(sort: \MinerUpdate.timestamp, order: .reverse) private var allUpdates: [MinerUpdate]
    
    @State private var isRefreshing = false
    @State private var searchText = ""
    @State private var showingAddMiner = false
    @State private var minerToDelete: Miner?
    @State private var sortOption: MinerSortOption = .name
    @State private var sortAscending = true
    @State private var backgroundRefreshTimer: Timer?
    
    // Settings
    @AppStorage("refreshInterval") private var refreshInterval = 30
    
    // Get totals from latest update of each online miner
    private var onlineMinerStats: (hashRate: Double, power: Double) {
        let onlineMacAddresses = Set(miners.filter { !$0.isOffline }.map { $0.macAddress })
        var latestHashByMac: [String: Double] = [:]
        var latestPowerByMac: [String: Double] = [:]
        
        for update in allUpdates {
            if onlineMacAddresses.contains(update.macAddress) {
                if latestHashByMac[update.macAddress] == nil {
                    latestHashByMac[update.macAddress] = update.hashRate
                    latestPowerByMac[update.macAddress] = update.power
                }
            }
        }
        
        return (
            hashRate: latestHashByMac.values.reduce(0, +),
            power: latestPowerByMac.values.reduce(0, +)
        )
    }
    
    private var formattedTotalHashRate: FormattedHashRate {
        formatMinerHashRate(rawRateValue: onlineMinerStats.hashRate)
    }
    
    private var totalPower: Double {
        onlineMinerStats.power
    }
    
    // Get latest update for each miner by MAC address
    private var latestUpdateByMac: [String: MinerUpdate] {
        var result: [String: MinerUpdate] = [:]
        for update in allUpdates {
            if result[update.macAddress] == nil {
                result[update.macAddress] = update
            }
        }
        return result
    }
    
    private var filteredMiners: [Miner] {
        var result = miners
        
        // Filter by search
        if !searchText.isEmpty {
            result = result.filter {
                $0.hostName.localizedCaseInsensitiveContains(searchText) ||
                $0.ipAddress.contains(searchText)
            }
        }
        
        // Sort
        let updates = latestUpdateByMac
        result.sort { miner1, miner2 in
            let update1 = updates[miner1.macAddress]
            let update2 = updates[miner2.macAddress]
            
            let comparison: Bool
            switch sortOption {
            case .name:
                comparison = miner1.hostName.localizedCaseInsensitiveCompare(miner2.hostName) == .orderedAscending
            case .hashRate:
                let rate1 = update1?.hashRate ?? 0
                let rate2 = update2?.hashRate ?? 0
                comparison = rate1 > rate2 // Higher is better, so descending by default
            case .temperature:
                let temp1 = update1?.temp ?? 0
                let temp2 = update2?.temp ?? 0
                comparison = temp1 > temp2 // Higher first by default
            case .power:
                let power1 = update1?.power ?? 0
                let power2 = update2?.power ?? 0
                comparison = power1 > power2 // Higher first by default
            }
            
            return sortAscending ? comparison : !comparison
        }
        
        return result
    }
    
    var body: some View {
        Group {
            if miners.isEmpty {
                emptyStateView
            } else {
                minerList
            }
        }
        .navigationTitle("Miners")
        .searchable(text: $searchText, prompt: "Search miners")
        .refreshable {
            await refreshMiners()
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddMiner = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddMiner) {
            AddMinerView()
        }
    }
    
    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("No Miners", systemImage: "cpu")
        } description: {
            Text("Scan your network to find miners automatically, or add one by IP address")
        } actions: {
            Button {
                showingAddMiner = true
            } label: {
                Label("Add Miner", systemImage: "plus.circle")
            }
            .buttonStyle(.borderedProminent)
        }
    }
    
    private var minerList: some View {
        List {
            // Stats summary
            Section {
                MinerStatsSummaryCard(hashRate: formattedTotalHashRate, totalPower: totalPower)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
            
            // Miner list with inline counts and sort
            Section {
                ForEach(filteredMiners, id: \.macAddress) { miner in
                    NavigationLink(value: miner) {
                        MinerRowView(miner: miner)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            minerToDelete = miner
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            } header: {
                HStack {
                    Menu {
                        ForEach(MinerSortOption.allCases, id: \.self) { option in
                            Button {
                                if sortOption == option {
                                    sortAscending.toggle()
                                } else {
                                    sortOption = option
                                    sortAscending = option == .name
                                }
                            } label: {
                                Label {
                                    Text(option.rawValue)
                                } icon: {
                                    if sortOption == option {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text("Devices")
                                .foregroundStyle(.primary)
                            Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 8) {
                        Label("\(miners.filter { !$0.isOffline }.count) online", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                        
                        Text("•")
                            .foregroundStyle(.secondary)
                        
                        Text("\(miners.count) total")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .textCase(nil)
            }
        }
        .navigationDestination(for: Miner.self) { miner in
            MinerDetailView(miner: miner)
        }
        .alert("Delete Miner?", isPresented: Binding(
            get: { minerToDelete != nil },
            set: { if !$0 { minerToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) {
                minerToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let miner = minerToDelete {
                    deleteMiner(miner)
                }
                minerToDelete = nil
            }
        } message: {
            if let miner = minerToDelete {
                Text("Are you sure you want to remove \(miner.hostName)?")
            }
        }
        .onAppear {
            startBackgroundRefresh()
        }
        .onDisappear {
            stopBackgroundRefresh()
        }
        .onChange(of: refreshInterval) { _, _ in
            // Restart with new interval
            stopBackgroundRefresh()
            startBackgroundRefresh()
        }
    }
    
    private func refreshMiners() async {
        isRefreshing = true
        defer { isRefreshing = false }
        
        // Poll all miners in parallel
        await withTaskGroup(of: Void.self) { group in
            for miner in miners {
                group.addTask {
                    await self.pollMiner(miner)
                }
            }
        }
    }
    
    private func pollMiner(_ miner: Miner) async {
        let client = AxeOSClient(
            deviceIpAddress: miner.ipAddress,
            urlSession: .shared
        )
        
        let result = await client.getSystemInfo()
        
        await MainActor.run {
            switch result {
            case .success(let info):
                miner.consecutiveTimeoutErrors = 0
                
                // Update hostname if it changed on the miner
                if !info.hostname.isEmpty && miner.hostName != info.hostname {
                    miner.hostName = info.hostname
                }
                
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
    }
    
    private func startBackgroundRefresh() {
        guard refreshInterval > 0 else { return } // 0 = manual only
        
        // Initial refresh
        Task {
            await refreshMiners()
        }
        
        // Periodic refresh
        backgroundRefreshTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(refreshInterval), repeats: true) { _ in
            Task {
                await refreshMiners()
            }
        }
    }
    
    private func stopBackgroundRefresh() {
        backgroundRefreshTimer?.invalidate()
        backgroundRefreshTimer = nil
    }
    
    private func deleteMiner(_ miner: Miner) {
        // Delete associated MinerUpdate records first to prevent orphaned relationships
        let macAddress = miner.macAddress
        let updateDescriptor = FetchDescriptor<MinerUpdate>(
            predicate: #Predicate<MinerUpdate> { $0.macAddress == macAddress }
        )
        
        do {
            let updates = try modelContext.fetch(updateDescriptor)
            for update in updates {
                modelContext.delete(update)
            }
        } catch {
            print("Error cleaning up miner updates: \(error)")
        }
        
        // Now delete the miner
        withAnimation {
            modelContext.delete(miner)
        }
        
        // Save context to ensure clean state
        do {
            try modelContext.save()
        } catch {
            print("Error saving after miner deletion: \(error)")
        }
    }
}

// MARK: - Miner Row

struct MinerRowView: View {
    let miner: Miner
    @Query private var updates: [MinerUpdate]
    
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
    
    var body: some View {
        HStack(spacing: 12) {
            // Miner icon with status indicator
            ZStack(alignment: .bottomTrailing) {
                Image(miner.minerType.imageName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 48, height: 48)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                
                // Status dot
                Circle()
                    .fill(miner.isOffline ? Color.red : Color.green)
                    .frame(width: 12, height: 12)
                    .overlay(
                        Circle()
                            .stroke(Color(.systemBackground), lineWidth: 2)
                    )
                    .offset(x: 2, y: 2)
            }
            
            // Info column
            VStack(alignment: .leading, spacing: 3) {
                Text(miner.hostName)
                    .font(.system(.body, weight: .semibold))
                    .lineLimit(1)
                
                Text(miner.minerDeviceDisplayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                
                // Stats row - only show if we have data
                if let update = latestUpdate {
                    HStack(spacing: 12) {
                        // Hash rate
                        let formatted = formatMinerHashRate(rawRateValue: update.hashRate)
                        HStack(spacing: 3) {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(.green)
                            Text("\(formatted.rateString) \(formatted.rateSuffix)")
                                .font(.system(.caption, design: .rounded, weight: .medium))
                                .foregroundStyle(.primary)
                        }
                        
                        // Temperature pill
                        if let temp = update.temp {
                            TemperaturePill(temp: temp)
                        }
                        
                        // Power
                        HStack(spacing: 3) {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(.orange)
                            Text(String(format: "%.0fW", update.power))
                                .font(.system(.caption, design: .rounded, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Temperature Pill

struct TemperaturePill: View {
    let temp: Double
    
    private var color: Color {
        if temp >= 70 { return .red }
        if temp >= 55 { return .orange }
        return .green
    }
    
    var body: some View {
        HStack(spacing: 2) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(String(format: "%.0f°", temp))
                .font(.system(.caption, design: .rounded, weight: .medium))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.15))
        .clipShape(Capsule())
    }
}

// MARK: - Miner Stats Summary Card

struct MinerStatsSummaryCard: View {
    let hashRate: FormattedHashRate
    let totalPower: Double
    
    var body: some View {
        HStack(spacing: 0) {
            // Hash Rate
            VStack(spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(hashRate.rateString)
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    
                    Text(hashRate.rateSuffix)
                        .font(.system(.body, design: .rounded, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                
                Label("Hash Rate", systemImage: "bolt.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
            .frame(maxWidth: .infinity)
            
            // Divider
            Rectangle()
                .fill(Color(.separator))
                .frame(width: 1, height: 50)
            
            // Power
            VStack(spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(String(format: "%.0f", totalPower))
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    
                    Text("W")
                        .font(.system(.body, design: .rounded, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                
                Label("Power", systemImage: "bolt.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 16)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

#Preview {
    NavigationStack {
        MinerListView()
    }
    .modelContainer(try! createModelContainer(inMemory: true))
}

