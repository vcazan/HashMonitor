//
//  ContentView.swift
//  HashRipper
//
//  Created by Matt Sellars
//

import SwiftUI
import SwiftData
import AppKit
import os.log

let kToolBarItemSize = CGSize(width: 44, height: 44)

enum SidebarTab: String, CaseIterable {
    case miners = "miners"
    case alerts = "alerts"
    case profiles = "profiles"
    case firmware = "firmware"
    case settings = "settings"
}

struct MainContentView: View {
    var logger: Logger {
        HashRipperLogger.shared.loggerForCategory("MainContentView")
    }

    @Environment(\.openWindow) private var openWindow
    @Environment(\.modelContext) private var modelContext
    @Environment(\.newMinerScanner) private var deviceRefresher
    @Environment(\.minerClientManager) private var minerClientManager
    @Environment(\.database) private var database
    @Environment(\.firmwareReleaseViewModel) private var firmwareReleaseViewModel
    @Environment(\.colorScheme) private var colorScheme

    @State var isShowingChartsInspector: Bool = false
    @State var isShowingSettingsInspector: Bool = false
    @State private var selectedTab: SidebarTab = .miners
    @State private var selectedMiner: Miner? = nil
    @State private var showAddMinerSheet: Bool = false
    @State private var showManualMinerSheet: Bool = false
    @State private var showProfileRolloutSheet: Bool = false
    @State private var offlineMinersCount: Int = 0
    
    // Miner list state
    @State private var miners: [Miner] = []
    @State private var searchText: String = ""
    @State private var debounceTask: Task<Void, Never>?
    
    // Scan result feedback
    @State private var newlyDiscoveredMinerMACs: Set<String> = []
    @State private var showScanResultBanner: Bool = false
    @State private var scanResultMessage: String = ""
    @State private var scanResultIsSuccess: Bool = true
    
    // WatchDog alerts
    @Query(
        filter: #Predicate<WatchDogActionLog> { !$0.isRead },
        sort: [SortDescriptor<WatchDogActionLog>(\.timestamp, order: .reverse)]
    ) private var unreadActions: [WatchDogActionLog]
    
    private var unreadAlertCount: Int {
        unreadActions.count
    }
    
    private var filteredMiners: [Miner] {
        if searchText.isEmpty {
            return miners
        }
        let query = searchText.lowercased()
        return miners.filter { miner in
            miner.hostName.lowercased().contains(query) ||
            miner.minerDeviceDisplayName.lowercased().contains(query) ||
            miner.ipAddress.lowercased().contains(query)
        }
    }
    
    private var inspectorBinding: Binding<Bool> {
        Binding(
            get: { isShowingChartsInspector || isShowingSettingsInspector },
            set: { newValue in
                if !newValue {
                    isShowingChartsInspector = false
                    isShowingSettingsInspector = false
                }
            }
        )
    }

    var body: some View {
        NavigationSplitView(
            sidebar: { sidebarContent },
            detail: { detailWithResizableInspector }
        )
        .navigationSplitViewStyle(.balanced)
        .task {
            // Note: We don't auto-scan for new miners on app launch.
            // Scanning only happens when user clicks the scan button.
            // The MinerClientManager handles pinging existing miners to update their status.
            loadMiners()
            updateStats()
            while !Task.isCancelled {
                updateOfflineCount()
                updateStats()
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .minerUpdateInserted)) { _ in
            debounceTask?.cancel()
            debounceTask = Task {
                try? await Task.sleep(nanoseconds: 500_000_000)
                if !Task.isCancelled {
                    loadMiners()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .minerRemoved)) { _ in
            // Deselect the miner and close inspectors
            selectedMiner = nil
            isShowingChartsInspector = false
            isShowingSettingsInspector = false
            loadMiners()
        }
        .onReceive(NotificationCenter.default.publisher(for: .showAlertsTab)) { _ in
            // Switch to alerts tab when requested from status bar
            selectedTab = .alerts
            selectedMiner = nil
            isShowingChartsInspector = false
            isShowingSettingsInspector = false
        }
        .sheet(isPresented: $showAddMinerSheet, onDismiss: {
            // Reload miners after wizard closes
            loadMiners()
        }) {
            NewMinerSetupWizardView(onCancel: { showAddMinerSheet = false })
                .frame(width: 800, height: 700)
                .toolbar(.hidden)
        }
        .sheet(isPresented: $showManualMinerSheet, onDismiss: {
            // Reload miners after adding a new one
            loadMiners()
        }) {
            ManualMinerAddView(onDismiss: { showManualMinerSheet = false })
        }
        .sheet(isPresented: $showProfileRolloutSheet) {
            MinerProfileRolloutWizard { showProfileRolloutSheet = false }
        }
    }
    
    // MARK: - Sidebar with Miners List
    
    private var sidebarContent: some View {
        VStack(spacing: 0) {
            // Header with title, scan and add buttons
            HStack(spacing: 8) {
                Text("Miners")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                
                // Scanning indicator
                if deviceRefresher?.isScanning == true {
                    HStack(spacing: 3) {
                        ProgressView()
                            .scaleEffect(0.5)
                            .controlSize(.mini)
                        Text("Scanning")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                }
                
                Spacer()
                
                // Scan for miners
                Button(action: scanForNewMiners) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(deviceRefresher?.isScanning == true ? .blue : .secondary)
                }
                .buttonStyle(.plain)
                .help("Scan network for miners")
                .disabled(deviceRefresher?.isScanning ?? false)
                
                addMinerMenu
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 8)
            
            // Search field
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                
                TextField("Search...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear search")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(colorScheme == .dark ? Color(white: 0.15) : Color(white: 0.94))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            
            Divider()
                .padding(.horizontal, 12)
            
            // Scan result banner
            if showScanResultBanner {
                HStack(spacing: 8) {
                    Image(systemName: scanResultIsSuccess ? "checkmark.circle.fill" : "info.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(scanResultIsSuccess ? .green : .secondary)
                    
                    Text(scanResultMessage)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(scanResultIsSuccess ? .primary : .secondary)
                    
                    Spacer()
                    
                    Button(action: {
                        withAnimation { showScanResultBanner = false }
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(scanResultIsSuccess ? Color.green.opacity(0.1) : Color.secondary.opacity(0.1))
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            
            // Miners List
            ScrollView {
                LazyVStack(spacing: 2) {
                    // Dashboard row - native macOS sidebar style
                    let isDashboardSelected = selectedMiner == nil && selectedTab == .miners
                    
                    Button {
                        selectedMiner = nil
                        selectedTab = .miners
                        isShowingChartsInspector = false
                        isShowingSettingsInspector = false
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "rectangle.3.group")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(isDashboardSelected ? .white : .secondary)
                            
                            Text("Overview")
                                .font(.system(size: 12))
                                .foregroundStyle(isDashboardSelected ? .white : .primary)
                            
                            Spacer()
                            
                            Text("\(miners.count)")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(isDashboardSelected ? .white.opacity(0.8) : .secondary.opacity(0.6))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(isDashboardSelected ? Color.accentColor : Color.clear)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 4)
                    
                    ForEach(filteredMiners, id: \.macAddress) { miner in
                        SidebarMinerRow(
                            miner: miner,
                            isSelected: selectedMiner?.macAddress == miner.macAddress,
                            isNewlyDiscovered: newlyDiscoveredMinerMACs.contains(miner.macAddress)
                        ) {
                            selectedMiner = miner
                            selectedTab = .miners
                            // Clear "new" status when selected
                            newlyDiscoveredMinerMACs.remove(miner.macAddress)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            }
            
            Spacer(minLength: 0)
            
            // Bottom section: Stats + Tabs
            VStack(spacing: 0) {
                Divider()
                    .padding(.horizontal, 12)
                
                // Compact stats
                compactStatsView
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                
                Divider()
                    .padding(.horizontal, 12)
                
                // Tab buttons for Alerts, Profiles, Firmware & Settings
                HStack(spacing: 0) {
                    SidebarTabButton(
                        icon: "shield.checkered",
                        title: "Alerts",
                        isSelected: selectedTab == .alerts,
                        badgeCount: unreadAlertCount
                    ) {
                        selectedTab = .alerts
                        selectedMiner = nil
                    }
                    
                    SidebarTabButton(
                        icon: "square.stack.3d.up",
                        title: "Profiles",
                        isSelected: selectedTab == .profiles
                    ) {
                        selectedTab = .profiles
                        selectedMiner = nil
                    }
                    
                    SidebarTabButton(
                        icon: "arrow.down.circle",
                        title: "Firmware",
                        isSelected: selectedTab == .firmware
                    ) {
                        selectedTab = .firmware
                        selectedMiner = nil
                    }
                    
                    SidebarTabButton(
                        icon: "gearshape",
                        title: "Settings",
                        isSelected: selectedTab == .settings
                    ) {
                        selectedTab = .settings
                        selectedMiner = nil
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            }
        }
        .frame(minWidth: 240, idealWidth: 280, maxWidth: 320)
        .background(Color(nsColor: .windowBackgroundColor))
        .toolbar(.hidden)
    }
    
    private var addMinerMenu: some View {
        Menu {
            Button(action: addMinerManually) {
                Label("Add by IP Address", systemImage: "network")
            }
            
            Divider()
            
            Button(action: addNewMiner) {
                Label("Setup New Miner (AP Mode)", systemImage: "wifi")
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.blue)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .help("Add miner")
    }
    
    private var compactStatsView: some View {
        HStack(spacing: 16) {
            // Hash Rate
            HStack(spacing: 4) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                HStack(spacing: 2) {
                    Text(formattedTotalHashRate.0)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                    Text(formattedTotalHashRate.1)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
            
            // Miners online
            HStack(spacing: 4) {
                Image(systemName: "cpu")
                    .font(.system(size: 10))
                    .foregroundStyle(.blue)
                HStack(spacing: 2) {
                    Text("\(onlineMinerCount)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.green)
                    Text("/\(totalMinerCount)")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            
            // Power
            HStack(spacing: 4) {
                Image(systemName: "power")
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
                HStack(spacing: 2) {
                    Text("\(Int(totalPower))")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                    Text("W")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
    
    // Computed stats properties
    @State private var totalMinerCount: Int = 0
    @State private var onlineMinerCount: Int = 0
    @State private var totalPower: Double = 0
    @State private var totalHashRate: Double = 0
    
    private var formattedTotalHashRate: (String, String) {
        let result = formatMinerHashRate(rawRateValue: totalHashRate)
        return (result.rateString, result.rateSuffix)
    }
    
    // MARK: - Detail Content with Resizable Inspector
    
    @State private var inspectorWidth: CGFloat = 380
    
    @ViewBuilder
    private var detailWithResizableInspector: some View {
        let showingInspector = isShowingChartsInspector || isShowingSettingsInspector
        
        GeometryReader { geometry in
            HStack(spacing: 0) {
                detailContent
                    .frame(minWidth: 400, maxWidth: .infinity)
                    .layoutPriority(1)
                
                if showingInspector, let miner = selectedMiner {
                    // Draggable divider
                    Rectangle()
                        .fill(Color(nsColor: .separatorColor))
                        .frame(width: 1)
                        .contentShape(Rectangle().inset(by: -4))
                        .onHover { hovering in
                            if hovering {
                                NSCursor.resizeLeftRight.push()
                            } else {
                                NSCursor.pop()
                            }
                        }
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    let newWidth = inspectorWidth - value.translation.width
                                    // Ensure inspector doesn't take more than half the available width
                                    let maxAllowed = min(600, geometry.size.width * 0.5)
                                    inspectorWidth = min(max(newWidth, 300), maxAllowed)
                                }
                        )
                    
                    Group {
                        if isShowingSettingsInspector {
                            MinerSettingsInspector(miner: miner, isPresented: $isShowingSettingsInspector)
                        } else if isShowingChartsInspector {
                            MinerChartsInspector(miner: miner, isPresented: $isShowingChartsInspector)
                        }
                    }
                    .frame(width: min(inspectorWidth, geometry.size.width * 0.5))
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: showingInspector)
    }
    
    // MARK: - Detail Content
    
    private var detailContent: some View {
        Group {
            // Content based on selection
            switch selectedTab {
            case .miners:
                if let miner = selectedMiner {
                    MinerDetailView(
                        miner: miner,
                        showChartsInspector: $isShowingChartsInspector,
                        showSettingsInspector: $isShowingSettingsInspector,
                        addNewMiner: addNewMiner,
                        addMinerManually: addMinerManually,
                        rolloutProfile: rolloutProfile
                    )
                    .id(miner.macAddress)
                } else {
                    // Show dashboard overview when no miner selected
                    MiningDashboardView(selectedMiner: $selectedMiner)
                        .id("dashboard")
                }
            case .alerts:
                AlertsView()
                    .id("alerts")
            case .profiles:
                MinerProfilesView()
                    .navigationTitle("")
                    .toolbar(.hidden, for: .windowToolbar)
            case .firmware:
                FirmwareReleasesView()
                    .navigationTitle("")
                    .toolbar(.hidden, for: .windowToolbar)
            case .settings:
                AppSettingsView()
                    .id("settings")
            }
        }
        .transition(.opacity)
        .animation(.easeOut(duration: 0.12), value: selectedMiner?.macAddress)
        .animation(.easeOut(duration: 0.12), value: selectedTab)
    }
    
    // MARK: - Actions
    
    private func rolloutProfile() { showProfileRolloutSheet = true }
    private func addNewMiner() { showAddMinerSheet = true }
    private func addMinerManually() { showManualMinerSheet = true }
    private func scanForNewMiners() {
        Task {
            // Track existing miners before scan
            let existingMACs = Set(miners.map { $0.macAddress })
            
            // Start the scan (this returns immediately, scan runs in background)
            await deviceRefresher?.rescanDevicesStreaming()
            
            // Wait for scan to actually complete by polling isScanning
            // The rescanDevicesStreaming uses Task.detached so we need to wait
            while deviceRefresher?.isScanning == true {
                try? await Task.sleep(nanoseconds: 200_000_000) // 200ms
            }
            
            // Give a moment for database writes to complete
            try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
            
            // Reload and check for new miners
            await MainActor.run {
                loadMiners()
                
                let currentMACs = Set(miners.map { $0.macAddress })
                let newMACs = currentMACs.subtracting(existingMACs)
                
                if !newMACs.isEmpty {
                    // Mark new miners as discovered
                    newlyDiscoveredMinerMACs = newMACs
                    scanResultMessage = "Found \(newMACs.count) new miner\(newMACs.count == 1 ? "" : "s")!"
                    scanResultIsSuccess = true
                    
                    // Auto-select first new miner
                    if let firstNewMiner = miners.first(where: { newMACs.contains($0.macAddress) }) {
                        selectedMiner = firstNewMiner
                    }
                } else {
                    scanResultMessage = "Scan complete – no new miners found"
                    scanResultIsSuccess = false
                }
                
                // Show banner
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    showScanResultBanner = true
                }
                
                // Auto-hide banner after 4 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                    withAnimation(.easeOut(duration: 0.3)) {
                        showScanResultBanner = false
                    }
                }
                
                // Clear "new" highlights after 10 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                    withAnimation {
                        newlyDiscoveredMinerMACs.removeAll()
                    }
                }
            }
        }
    }
    
    private func loadMiners() {
        do {
            miners = try modelContext.fetch(FetchDescriptor<Miner>(sortBy: [SortDescriptor(\.hostName)]))
        } catch {
            logger.error("Failed to load miners: \(String(describing: error))")
        }
    }

    private func updateOfflineCount() {
        Task {
            let count = await database.withModelContext { context in
                do {
                    let miners = try context.fetch(FetchDescriptor<Miner>())
                    return miners.filter { $0.isOffline }.count
                } catch {
                    logger.error("Failed to fetch offline count: \(String(describing: error))")
                    return 0
                }
            }
            await MainActor.run { offlineMinersCount = count }
        }
    }
    
    private func updateStats() {
        Task {
            let stats = await database.withModelContext { context -> (total: Int, online: Int, power: Double, hashRate: Double) in
                do {
                    let miners = try context.fetch(FetchDescriptor<Miner>())
                    let total = miners.count
                    let online = miners.filter { !$0.isOffline }.count
                    
                    var totalPower: Double = 0
                    var totalHash: Double = 0
                    
                    for miner in miners {
                        let macAddress = miner.macAddress
                        var updateDescriptor = FetchDescriptor<MinerUpdate>(
                            predicate: #Predicate<MinerUpdate> { $0.macAddress == macAddress },
                            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
                        )
                        updateDescriptor.fetchLimit = 1
                        
                        if let update = try? context.fetch(updateDescriptor).first {
                            totalPower += update.power
                            totalHash += update.hashRate
                        }
                    }
                    
                    return (total, online, totalPower, totalHash)
                } catch {
                    return (0, 0, 0, 0)
                }
            }
            
            await MainActor.run {
                totalMinerCount = stats.total
                onlineMinerCount = stats.online
                totalPower = stats.power
                totalHashRate = stats.hashRate
            }
        }
    }

    private func reconnectOfflineMiners() {
        Task {
            logger.info("🔄 Reconnecting \(offlineMinersCount) offline miner(s)")
            await database.withModelContext { context in
                do {
                    let miners = try context.fetch(FetchDescriptor<Miner>())
                    for miner in miners.filter({ $0.isOffline }) {
                        miner.consecutiveTimeoutErrors = 0
                    }
                    try context.save()
                } catch {
                    logger.error("Failed to reset offline miners: \(String(describing: error))")
                }
            }
            if let scanner = deviceRefresher {
                await scanner.rescanDevicesStreaming()
            }
            updateOfflineCount()
        }
    }
}

// MARK: - Sidebar Miner Row

private struct SidebarMinerRow: View {
    let miner: Miner
    let isSelected: Bool
    var isNewlyDiscovered: Bool = false
    let action: () -> Void
    
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.modelContext) private var modelContext
    @State private var latestUpdate: MinerUpdate?
    @State private var isDataUpdating: Bool = false
    @State private var pulseAnimation: Bool = false
    
    private var rowBackgroundColor: Color {
        if isNewlyDiscovered {
            return Color.green.opacity(pulseAnimation ? 0.15 : 0.08)
        } else if isSelected {
            return colorScheme == .dark ? Color.blue.opacity(0.25) : Color.blue.opacity(0.12)
        } else {
            return colorScheme == .dark ? Color.white.opacity(0.03) : Color.black.opacity(0.02)
        }
    }
    
    private var rowBorderColor: Color {
        if isNewlyDiscovered {
            return Color.green.opacity(pulseAnimation ? 0.6 : 0.3)
        }
        return .clear
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                // Miner icon
                Image.icon(forMinerType: miner.minerType)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 32, height: 32)
                
                // Name and model
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(miner.hostName)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                        
                        Circle()
                            .fill(miner.isOffline ? Color.red : Color.green)
                            .frame(width: 6, height: 6)
                            .animation(.easeInOut(duration: 0.3), value: miner.isOffline)
                    }
                    
                    Text(miner.minerDeviceDisplayName)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                // Hash rate with animation
                if let update = latestUpdate, !miner.isOffline {
                    let formatted = formatMinerHashRate(rawRateValue: update.hashRate)
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(verbatim: formatted.rateString)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(isDataUpdating ? .green : .primary)
                            .contentTransition(.numericText())
                            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: formatted.rateString)
                        Text(formatted.rateSuffix)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(rowBackgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(rowBorderColor, lineWidth: 1.5)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.green.opacity(isDataUpdating ? 0.06 : 0))
            )
            .overlay(alignment: .topTrailing) {
                if isNewlyDiscovered {
                    Text("NEW")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.green)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                        .offset(x: -4, y: 4)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .contentShape(Rectangle())
            .animation(.easeOut(duration: 0.4), value: isDataUpdating)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulseAnimation)
        }
        .buttonStyle(.plain)
        .onAppear {
            loadLatestUpdate()
            if isNewlyDiscovered {
                pulseAnimation = true
            }
        }
        .onChange(of: isNewlyDiscovered) { _, newValue in
            pulseAnimation = newValue
        }
        .onReceive(NotificationCenter.default.publisher(for: .minerUpdateInserted)) { notification in
            if let macAddress = notification.userInfo?["macAddress"] as? String,
               macAddress == miner.macAddress {
                // Trigger subtle update animation
                withAnimation(.easeIn(duration: 0.1)) {
                    isDataUpdating = true
                }
                loadLatestUpdate()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    withAnimation(.easeOut(duration: 0.4)) {
                        isDataUpdating = false
                    }
                }
            }
        }
    }
    
    private func loadLatestUpdate() {
        let mac = miner.macAddress
        var descriptor = FetchDescriptor<MinerUpdate>(
            predicate: #Predicate<MinerUpdate> { $0.macAddress == mac },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        latestUpdate = try? modelContext.fetch(descriptor).first
    }
}

// MARK: - Sidebar Tab Button

private struct SidebarTabButton: View {
    let icon: String
    let title: String
    let isSelected: Bool
    var badgeCount: Int = 0
    let action: () -> Void
    
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(isSelected ? .blue : .secondary)
                    
                    // Badge
                    if badgeCount > 0 {
                        Text(badgeCount > 9 ? "9+" : "\(badgeCount)")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.red)
                            .clipShape(Capsule())
                            .offset(x: 8, y: -4)
                    }
                }
                
                Text(title)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(isSelected ? .blue : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                isSelected
                    ? (colorScheme == .dark ? Color.blue.opacity(0.15) : Color.blue.opacity(0.08))
                    : Color.clear
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}

