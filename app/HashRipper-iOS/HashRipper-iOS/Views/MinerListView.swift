//
//  MinerListView.swift
//  HashMonitor
//
//  Apple Design Language - Home App inspired
//

import SwiftUI
import SwiftData
import HashRipperKit
import AxeOSClient

// MARK: - Main View

struct MinerListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Miner.hostName) private var miners: [Miner]
    
    @State private var searchText = ""
    @State private var showAddMiner = false
    @State private var selectedSort: SortOption = .name
    @State private var isRefreshing = false
    @State private var minerToDelete: Miner? = nil
    @State private var showDeleteConfirmation = false
    
    // Aggregate stats
    @State private var totalHashRate: Double = 0
    @State private var totalPower: Double = 0
    @State private var onlineCount: Int = 0
    
    // Cached updates for UI
    @State private var latestUpdates: [String: MinerUpdate] = [:]
    
    private let session = URLSession.shared
    
    enum SortOption: String, CaseIterable {
        case name = "Name"
        case hashRate = "Hash Rate"
        case temperature = "Temperature"
        case status = "Status"
        
        var icon: String {
            switch self {
            case .name: return "textformat"
            case .hashRate: return "cube"
            case .temperature: return "thermometer.medium"
            case .status: return "circle.fill"
            }
        }
    }
    
    var filteredMiners: [Miner] {
        let filtered = searchText.isEmpty
            ? miners
            : miners.filter {
                $0.hostName.localizedCaseInsensitiveContains(searchText) ||
                $0.ipAddress.localizedCaseInsensitiveContains(searchText)
            }
        
        return filtered.sorted { m1, m2 in
            let update1 = latestUpdates[m1.macAddress]
            let update2 = latestUpdates[m2.macAddress]
            
            switch selectedSort {
            case .name:
                return m1.hostName.localizedCompare(m2.hostName) == .orderedAscending
            case .hashRate:
                return (update1?.hashRate ?? 0) > (update2?.hashRate ?? 0)
            case .temperature:
                return (update1?.temp ?? 0) > (update2?.temp ?? 0)
            case .status:
                return m1.isOnline && !m2.isOnline
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                AppColors.backgroundGrouped
                    .ignoresSafeArea()
                
                if miners.isEmpty {
                    emptyState
                } else {
                    mainContent
                }
            }
            .navigationTitle("Miners")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: Miner.self) { miner in
                MinerDetailView(miner: miner)
            }
            .searchable(text: $searchText, prompt: "Search miners...")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Haptics.impact(.light)
                        showAddMiner = true
                    } label: {
                        Image(systemName: "plus")
                            .fontWeight(.semibold)
                    }
                }
                
                ToolbarItem(placement: .secondaryAction) {
                    sortMenu
                }
            }
            .sheet(isPresented: $showAddMiner) {
                AddMinerView()
            }
            .refreshable {
                await refreshAllMiners()
            }
            .task {
                await initialLoad()
            }
            .alert("Delete Miner", isPresented: $showDeleteConfirmation, presenting: minerToDelete) { miner in
                Button("Delete", role: .destructive) {
                    deleteMiner(miner)
                }
                Button("Cancel", role: .cancel) { }
            } message: { miner in
                Text("Remove \"\(miner.hostName)\" from your miners? This cannot be undone.")
            }
        }
    }
    
    // MARK: - Components
    
    private var emptyState: some View {
        EmptyStateView(
            icon: "cpu",
            title: "No Miners Yet",
            message: "Add your first Bitcoin miner to start monitoring hash rate, temperature, and more.",
            buttonTitle: "Add Miner",
            action: { showAddMiner = true }
        )
    }
    
    private var mainContent: some View {
        ScrollView {
            LazyVStack(spacing: Spacing.lg) {
                // Stats Overview
                if !miners.isEmpty {
                    statsOverview
                        .padding(.horizontal)
                }
                
                // Miners List
                minersSection
            }
            .padding(.vertical)
        }
    }
    
    private var statsOverview: some View {
        HStack(spacing: Spacing.md) {
            // Total Hash Rate
            StatCard(
                icon: "cube.fill",
                value: formatHashRate(totalHashRate),
                label: "Total Hash Rate",
                color: AppColors.hashRate
            )
            
            // Online Status
            StatCard(
                icon: "circle.fill",
                value: "\(onlineCount)/\(miners.count)",
                label: "Online",
                color: onlineCount == miners.count ? AppColors.statusOnline : AppColors.statusWarning
            )
            
            // Total Power
            StatCard(
                icon: "bolt.fill",
                value: String(format: "%.0f W", totalPower),
                label: "Power",
                color: AppColors.power
            )
        }
    }
    
    private var minersSection: some View {
        VStack(spacing: Spacing.sm) {
            SectionHeader(title: "Devices", count: filteredMiners.count)
                .padding(.horizontal)
            
            ForEach(filteredMiners) { miner in
                NavigationLink(value: miner) {
                    MinerCard(
                        miner: miner,
                        latestUpdate: latestUpdates[miner.macAddress],
                        onDelete: {
                            minerToDelete = miner
                            showDeleteConfirmation = true
                        }
                    )
                }
                .buttonStyle(PressableStyle())
            }
            .padding(.horizontal)
        }
    }
    
    private var sortMenu: some View {
        Menu {
            ForEach(SortOption.allCases, id: \.self) { option in
                Button {
                    Haptics.selection()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        selectedSort = option
                    }
                } label: {
                    Label(option.rawValue, systemImage: option.icon)
                    if selectedSort == option {
                        Image(systemName: "checkmark")
                    }
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
                .fontWeight(.medium)
        }
    }
    
    // MARK: - Functions
    
    private func formatHashRate(_ ghPerSec: Double) -> String {
        if ghPerSec >= 1000 {
            return String(format: "%.1f TH", ghPerSec / 1000)
        } else {
            return String(format: "%.0f GH", ghPerSec)
        }
    }
    
    private func initialLoad() async {
        loadCachedUpdates()
        await refreshAllMiners()
    }
    
    private func loadCachedUpdates() {
        for miner in miners {
            if let update = miner.getLatestUpdate(from: modelContext) {
                latestUpdates[miner.macAddress] = update
            }
        }
        updateAggregateStats()
    }
    
    private func refreshAllMiners() async {
        isRefreshing = true
        
        await withTaskGroup(of: Void.self) { group in
            for miner in miners {
                group.addTask {
                    await self.refreshMiner(miner)
                }
            }
        }
        
        await MainActor.run {
            loadCachedUpdates()
            isRefreshing = false
        }
    }
    
    private func refreshMiner(_ miner: Miner) async {
        let client = AxeOSClient(deviceIpAddress: miner.ipAddress, urlSession: session)
        let result = await client.getSystemInfo()
        
        switch result {
        case .success(let info):
            await MainActor.run {
                // Reset error count on success
                miner.consecutiveTimeoutErrors = 0
                
                // Update hostname if changed
                if !info.hostname.isEmpty && miner.hostName != info.hostname {
                    miner.hostName = info.hostname
                }
                
                // Create update record
                let update = MinerUpdate.from(miner: miner, info: info)
                modelContext.insert(update)
                
                // Cache for UI
                latestUpdates[miner.macAddress] = update
            }
        case .failure:
            await MainActor.run {
                miner.consecutiveTimeoutErrors += 1
            }
        }
    }
    
    private func updateAggregateStats() {
        totalHashRate = latestUpdates.values.reduce(0) { $0 + $1.hashRate }
        totalPower = latestUpdates.values.reduce(0) { $0 + $1.power }
        onlineCount = miners.filter { $0.isOnline }.count
    }
    
    private func deleteMiner(_ miner: Miner) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            // Delete associated updates first
            let macAddress = miner.macAddress
            let descriptor = FetchDescriptor<MinerUpdate>(
                predicate: #Predicate<MinerUpdate> { $0.macAddress == macAddress }
            )
            
            if let updates = try? modelContext.fetch(descriptor) {
                for update in updates {
                    modelContext.delete(update)
                }
            }
            
            // Remove from cache
            latestUpdates.removeValue(forKey: miner.macAddress)
            
            // Delete miner
            modelContext.delete(miner)
            
            try? modelContext.save()
            Haptics.notification(.success)
        }
    }
}

// MARK: - Stat Card

struct StatCard: View {
    let icon: String
    let value: String
    let label: String
    let color: Color
    
    @State private var hasAppeared = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(color)
                
                Text(label.uppercased())
                    .font(.captionSmall)
                    .foregroundStyle(AppColors.textTertiary)
                    .tracking(0.3)
            }
            
            Text(value)
                .font(.numericSmall)
                .foregroundStyle(AppColors.textPrimary)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(AppColors.backgroundGroupedSecondary)
        )
        .opacity(hasAppeared ? 1 : 0)
        .offset(y: hasAppeared ? 0 : 8)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                hasAppeared = true
            }
        }
    }
}

// MARK: - Miner Card

struct MinerCard: View {
    let miner: Miner
    let latestUpdate: MinerUpdate?
    let onDelete: () -> Void
    
    @State private var hasAppeared = false
    
    var body: some View {
        HStack(spacing: Spacing.md) {
            // Miner icon
            minerIcon
            
            // Info
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                HStack(spacing: Spacing.sm) {
                    Text(miner.hostName)
                        .font(.titleSmall)
                        .foregroundStyle(AppColors.textPrimary)
                        .lineLimit(1)
                    
                    StatusBadge(isOnline: miner.isOnline, showLabel: false)
                }
                
                Text(miner.ipAddress)
                    .font(.captionLarge)
                    .foregroundStyle(AppColors.textTertiary)
            }
            
            Spacer()
            
            // Stats
            if let update = latestUpdate, miner.isOnline {
                statsView(update: update)
            }
            
            // Chevron
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppColors.textQuaternary)
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(AppColors.backgroundGroupedSecondary)
        )
        .contextMenu {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .opacity(hasAppeared ? 1 : 0)
        .offset(y: hasAppeared ? 0 : 12)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.05)) {
                hasAppeared = true
            }
        }
    }
    
    private var minerIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(AppColors.fillTertiary)
                .frame(width: 44, height: 44)
            
            Image(miner.minerType.imageName)
                .resizable()
                .scaledToFit()
                .frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }
    
    private func statsView(update: MinerUpdate) -> some View {
        HStack(spacing: Spacing.sm) {
            // Hash rate
            VStack(alignment: .trailing, spacing: 0) {
                Text(formatHashRate(update.hashRate))
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppColors.textPrimary)
                    .contentTransition(.numericText())
                
                Text("GH/s")
                    .font(.captionSmall)
                    .foregroundStyle(AppColors.textTertiary)
            }
            
            // Temperature indicator
            if let temp = update.temp {
                temperaturePill(temp: temp)
            }
        }
    }
    
    private func temperaturePill(temp: Double) -> some View {
        let color = temperatureColor(temp)
        
        return HStack(spacing: Spacing.xxs) {
            Circle()
                .fill(color)
                .frame(width: 4, height: 4)
            
            Text(String(format: "%.0f°", temp))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(AppColors.textPrimary)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
    }
    
    private func formatHashRate(_ ghPerSec: Double) -> String {
        if ghPerSec >= 1000 {
            return String(format: "%.1f", ghPerSec / 1000)
        } else {
            return String(format: "%.0f", ghPerSec)
        }
    }
}

// MARK: - Preview

#Preview {
    MinerListView()
        .modelContainer(for: [Miner.self, MinerUpdate.self], inMemory: true)
}
