//
//  MinerListView.swift
//  HashRipper-iOS
//
//  Professional miner list with muted, sophisticated design
//

import SwiftUI
import SwiftData
import HashRipperKit
import AxeOSClient

enum MinerSortOption: String, CaseIterable, Identifiable {
    case name = "Name"
    case hashRate = "Hash Rate"
    case temperature = "Temperature"
    case power = "Power"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .name: return "textformat"
        case .hashRate: return "cube.fill"
        case .temperature: return "thermometer.medium"
        case .power: return "bolt.fill"
        }
    }
}

enum SortDirection {
    case ascending, descending
    
    mutating func toggle() {
        self = self == .ascending ? .descending : .ascending
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
    @State private var sortDirection: SortDirection = .ascending
    @State private var backgroundRefreshTimer: Timer?
    
    @AppStorage("refreshInterval") private var refreshInterval = 30
    
    // MARK: - Computed Properties
    
    private var onlineCount: Int {
        miners.filter { !$0.isOffline }.count
    }
    
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
        
        if !searchText.isEmpty {
            result = result.filter {
                $0.hostName.localizedCaseInsensitiveContains(searchText) ||
                $0.ipAddress.contains(searchText)
            }
        }
        
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
                comparison = rate1 > rate2
            case .temperature:
                let temp1 = update1?.temp ?? 0
                let temp2 = update2?.temp ?? 0
                comparison = temp1 > temp2
            case .power:
                let power1 = update1?.power ?? 0
                let power2 = update2?.power ?? 0
                comparison = power1 > power2
            }
            
            return sortDirection == .ascending ? comparison : !comparison
        }
        
        return result
    }
    
    // MARK: - Body
    
    var body: some View {
        Group {
            if miners.isEmpty {
                emptyStateView
            } else {
                minerListContent
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
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Picker("Sort By", selection: $sortOption) {
                        ForEach(MinerSortOption.allCases) { option in
                            Label(option.rawValue, systemImage: option.icon)
                                .tag(option)
                        }
                    }
                    .pickerStyle(.inline)
                    
                    Divider()
                    
                    Button {
                        sortDirection.toggle()
                    } label: {
                        Label(
                            sortDirection == .ascending ? "Ascending" : "Descending",
                            systemImage: sortDirection == .ascending ? "arrow.up" : "arrow.down"
                        )
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
            }
        }
        .sheet(isPresented: $showingAddMiner) {
            AddMinerView()
        }
        .alert("Remove Miner?", isPresented: Binding(
            get: { minerToDelete != nil },
            set: { if !$0 { minerToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) { minerToDelete = nil }
            Button("Remove", role: .destructive) {
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
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        EmptyStateView(
            icon: "cpu",
            title: "No Miners",
            message: "Scan your network to find miners, or add one manually by IP address",
            buttonTitle: "Add Miner"
        ) {
            showingAddMiner = true
        }
    }
    
    // MARK: - Miner List
    
    private var minerListContent: some View {
        List {
            // Stats Summary Card
            Section {
                StatsOverviewCard(
                    hashRate: formattedTotalHashRate,
                    power: onlineMinerStats.power,
                    onlineCount: onlineCount,
                    totalCount: miners.count
                )
                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                .listRowBackground(Color.clear)
            }
            
            // Miner List
            Section {
                ForEach(filteredMiners, id: \.macAddress) { miner in
                    NavigationLink(value: miner) {
                        MinerRowView(miner: miner)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            minerToDelete = miner
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Devices")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                    
                    Spacer()
                    
                    Text("\(onlineCount) online • \(miners.count) total")
                        .font(.system(size: 12))
                        .foregroundStyle(AppColors.subtleText)
                }
                .textCase(nil)
            }
        }
        .listStyle(.insetGrouped)
        .navigationDestination(for: Miner.self) { miner in
            MinerDetailView(miner: miner)
        }
        .onAppear { startBackgroundRefresh() }
        .onDisappear { stopBackgroundRefresh() }
        .onChange(of: refreshInterval) { _, _ in
            stopBackgroundRefresh()
            startBackgroundRefresh()
        }
    }
    
    // MARK: - Actions
    
    private func refreshMiners() async {
        isRefreshing = true
        defer { isRefreshing = false }
        
        await withTaskGroup(of: Void.self) { group in
            for miner in miners {
                group.addTask { await self.pollMiner(miner) }
            }
        }
    }
    
    private func pollMiner(_ miner: Miner) async {
        let client = AxeOSClient(deviceIpAddress: miner.ipAddress, urlSession: .shared)
        let result = await client.getSystemInfo()
        
        await MainActor.run {
            switch result {
            case .success(let info):
                miner.consecutiveTimeoutErrors = 0
                
                if !info.hostname.isEmpty && miner.hostName != info.hostname {
                    miner.hostName = info.hostname
                }
                
                let update = MinerUpdate(
                    miner: miner,
                    hostname: info.hostname,
                    stratumUser: info.stratumUser,
                    fallbackStratumUser: info.fallbackStratumUser,
                    stratumURL: info.stratumURL,
                    stratumPort: info.stratumPort,
                    fallbackStratumURL: info.fallbackStratumURL,
                    fallbackStratumPort: info.fallbackStratumPort,
                    minerFirmwareVersion: info.version,
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
                    isUsingFallbackStratum: info.isUsingFallbackStratum
                )
                modelContext.insert(update)
                
            case .failure:
                miner.consecutiveTimeoutErrors += 1
            }
        }
    }
    
    private func startBackgroundRefresh() {
        guard refreshInterval > 0 else { return }
        
        Task { await refreshMiners() }
        
        backgroundRefreshTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(refreshInterval), repeats: true) { _ in
            Task { await refreshMiners() }
        }
    }
    
    private func stopBackgroundRefresh() {
        backgroundRefreshTimer?.invalidate()
        backgroundRefreshTimer = nil
    }
    
    private func deleteMiner(_ miner: Miner) {
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
        
        withAnimation {
            modelContext.delete(miner)
        }
        
        do {
            try modelContext.save()
        } catch {
            print("Error saving after miner deletion: \(error)")
        }
    }
}

// MARK: - Stats Overview Card

struct StatsOverviewCard: View {
    let hashRate: FormattedHashRate
    let power: Double
    let onlineCount: Int
    let totalCount: Int
    
    var body: some View {
        HStack(spacing: 0) {
            // Hash Rate
            VStack(spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(hashRate.rateString)
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    
                    Text(hashRate.rateSuffix)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppColors.subtleText)
                }
                
                HStack(spacing: 4) {
                    Image(systemName: "cube.fill")
                        .font(.system(size: 10))
                    Text("Hash Rate")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(AppColors.hashRate)
            }
            .frame(maxWidth: .infinity)
            
            // Divider
            Rectangle()
                .fill(Color(.separator).opacity(0.5))
                .frame(width: 1, height: 44)
            
            // Power
            VStack(spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(String(format: "%.0f", power))
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    
                    Text("W")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppColors.subtleText)
                }
                
                HStack(spacing: 4) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 10))
                    Text("Power")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(AppColors.power)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 16)
        .background(AppColors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(AppColors.cardBorder, lineWidth: 0.5)
        )
    }
}

// MARK: - Miner Row View

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
    
    private var latestUpdate: MinerUpdate? { updates.first }
    
    var body: some View {
        HStack(spacing: 12) {
            // Miner icon with status
            ZStack(alignment: .bottomTrailing) {
                Image(miner.minerType.imageName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 44, height: 44)
                    .background(Color(.tertiarySystemFill))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                
                Circle()
                    .fill(miner.isOffline ? AppColors.error : AppColors.success)
                    .frame(width: 10, height: 10)
                    .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))
                    .offset(x: 2, y: 2)
            }
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(miner.hostName)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                
                Text(miner.minerDeviceDisplayName)
                    .font(.system(size: 12))
                    .foregroundStyle(AppColors.subtleText)
                    .lineLimit(1)
                
                // Stats row
                if let update = latestUpdate {
                    HStack(spacing: 10) {
                        let formatted = formatMinerHashRate(rawRateValue: update.hashRate)
                        StatBadge(
                            icon: "cube.fill",
                            value: formatted.rateString,
                            unit: formatted.rateSuffix,
                            color: AppColors.hashRate,
                            compact: true
                        )
                        
                        if let temp = update.temp {
                            TemperatureBadge(temp: temp)
                        }
                        
                        StatBadge(
                            icon: "bolt.fill",
                            value: String(format: "%.0f", update.power),
                            unit: "W",
                            color: AppColors.power,
                            compact: true
                        )
                    }
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Temperature Badge

struct TemperatureBadge: View {
    let temp: Double
    
    private var color: Color { temperatureColor(temp) }
    
    var body: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
            
            Text(String(format: "%.0f°", temp))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
    }
}

#Preview {
    NavigationStack {
        MinerListView()
    }
    .modelContainer(try! createModelContainer(inMemory: true))
}
