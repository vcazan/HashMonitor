//
//  AddMinerView.swift
//  HashMonitor
//
//  Apple Design Language - Clean, focused add flow
//

import SwiftUI
import SwiftData
import HashRipperKit
import AxeOSClient
import AvalonClient

struct AddMinerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var existingMiners: [Miner]
    
    @State private var selectedTab: AddMethod = .scan
    @State private var manualIP = ""
    @State private var isConnecting = false
    @State private var errorMessage: String?
    
    // Scanning state
    @State private var isScanning = false
    @State private var discoveredDevices: [DiscoveredDevice] = []
    @State private var networkRange = ""
    @State private var selectedDevices: Set<UUID> = []
    
    private let session = URLSession.shared
    
    enum AddMethod: String, CaseIterable {
        case scan = "Scan"
        case manual = "Manual"
    }
    
    /// Unified discovered device that can be either AxeOS or Avalon
    enum DiscoveredDeviceInfo {
        case axeOS(AxeOSDeviceInfo)
        case avalon(AvalonDeviceInfo)
        
        var hostname: String {
            switch self {
            case .axeOS(let info): return info.hostname
            case .avalon(let info): return info.hostname
            }
        }
        
        var uniqueId: String {
            switch self {
            case .axeOS(let info): return info.macAddr
            case .avalon(let info): return "avalon-\(info.hostname)"
            }
        }
        
        var displayName: String {
            switch self {
            case .axeOS(let info):
                return info.hostname.isEmpty ? "BitAxe" : info.hostname
            case .avalon(let info):
                return info.hostname.isEmpty ? "Avalon" : info.hostname
            }
        }
        
        var minerType: MinerType {
            switch self {
            case .axeOS(let info):
                return MinerType.from(boardVersion: info.boardVersion, deviceModel: info.deviceModel)
            case .avalon:
                return .Avalon
            }
        }
    }
    
    struct DiscoveredDevice: Identifiable {
        let id = UUID()
        let ipAddress: String
        let info: DiscoveredDeviceInfo
    }
    
    private var filteredDevices: [DiscoveredDevice] {
        let existingMACs = Set(existingMiners.map { $0.macAddress })
        return discoveredDevices.filter { device in
            !existingMACs.contains(device.info.uniqueId)
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                AppColors.backgroundGrouped
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Method picker
                    methodPicker
                        .padding(.horizontal)
                        .padding(.top, Spacing.md)
                    
                    // Content
                    TabView(selection: $selectedTab) {
                        scanView
                            .tag(AddMethod.scan)
                        
                        manualView
                            .tag(AddMethod.manual)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                }
            }
            .navigationTitle("Add Miner")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .task {
                await detectNetworkRange()
            }
        }
    }
    
    // MARK: - Method Picker
    
    private var methodPicker: some View {
        HStack(spacing: Spacing.xs) {
            ForEach(AddMethod.allCases, id: \.self) { method in
                Button {
                    Haptics.selection()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        selectedTab = method
                    }
                } label: {
                    Text(method.rawValue)
                        .font(.bodyMedium)
                        .fontWeight(selectedTab == method ? .semibold : .medium)
                        .foregroundStyle(selectedTab == method ? .white : AppColors.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.md)
                        .background(
                            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                                .fill(selectedTab == method ? Color.teal : .clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(AppColors.fillTertiary)
        )
    }
    
    // MARK: - Scan View
    
    private var scanView: some View {
        ScrollView {
            VStack(spacing: Spacing.xl) {
                // Network info card
                networkInfoCard
                
                // Scan button or results
                if discoveredDevices.isEmpty && !isScanning {
                    scanPrompt
                } else {
                    scanResults
                }
            }
            .padding()
        }
    }
    
    private var networkInfoCard: some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: "wifi")
                .font(.system(size: 20))
                .foregroundStyle(.teal)
            
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text("Network Range")
                    .font(.captionLarge)
                    .foregroundStyle(AppColors.textTertiary)
                
                Text(networkRange.isEmpty ? "Detecting..." : networkRange)
                    .font(.bodyMedium)
                    .fontWeight(.medium)
                    .foregroundStyle(AppColors.textPrimary)
            }
            
            Spacer()
            
            if isScanning {
                ProgressView()
                    .tint(.teal)
            }
        }
        .padding(Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(AppColors.backgroundGroupedSecondary)
        )
    }
    
    private var scanPrompt: some View {
        VStack(spacing: Spacing.xl) {
            // Illustration
            ZStack {
                Circle()
                    .stroke(AppColors.fillSecondary, lineWidth: 2)
                    .frame(width: 100, height: 100)
                
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 40))
                    .foregroundStyle(.teal)
            }
            .padding(.top, Spacing.xxxl)
            
            VStack(spacing: Spacing.sm) {
                Text("Find Miners")
                    .font(.titleMedium)
                    .foregroundStyle(AppColors.textPrimary)
                
                Text("Scan your local network to automatically discover Bitcoin miners running AxeOS or Avalon firmware.")
                    .font(.bodySmall)
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
            }
            
            Button {
                Haptics.impact(.medium)
                Task { await startScan() }
            } label: {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "magnifyingglass")
                    Text("Start Scan")
                }
                .font(.bodyMedium)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.lg)
                .background(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(.teal)
                )
            }
            .buttonStyle(PressableStyle())
            .disabled(networkRange.isEmpty || isScanning)
        }
        .frame(maxWidth: .infinity)
    }
    
    private var scanResults: some View {
        VStack(spacing: Spacing.lg) {
            // Header
            HStack {
                if isScanning {
                    HStack(spacing: Spacing.sm) {
                        ProgressView()
                            .tint(.teal)
                        
                        Text("Scanning...")
                            .font(.bodySmall)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                } else {
                    Text("\(filteredDevices.count) miner\(filteredDevices.count == 1 ? "" : "s") found")
                        .font(.bodySmall)
                        .foregroundStyle(AppColors.textSecondary)
                }
                
                Spacer()
                
                // Select all / Deselect all
                if !filteredDevices.isEmpty && !isScanning {
                    Button {
                        Haptics.selection()
                        if selectedDevices.count == filteredDevices.count {
                            selectedDevices.removeAll()
                        } else {
                            selectedDevices = Set(filteredDevices.map { $0.id })
                        }
                    } label: {
                        Text(selectedDevices.count == filteredDevices.count ? "Deselect All" : "Select All")
                            .font(.captionLarge)
                            .fontWeight(.medium)
                    }
                    .tint(.teal)
                }
                
                Button {
                    Haptics.impact(.light)
                    selectedDevices.removeAll()
                    Task { await startScan() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .medium))
                }
                .tint(.teal)
                .disabled(isScanning)
            }
            
            // Devices list
            if filteredDevices.isEmpty && !isScanning {
                VStack(spacing: Spacing.md) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 32))
                        .foregroundStyle(AppColors.statusOnline)
                    
                    Text("All discovered miners are already added")
                        .font(.bodySmall)
                        .foregroundStyle(AppColors.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.xxxl)
            } else {
                ForEach(filteredDevices) { device in
                    DiscoveredDeviceRow(
                        device: device,
                        isSelected: selectedDevices.contains(device.id),
                        onToggle: {
                            Haptics.selection()
                            if selectedDevices.contains(device.id) {
                                selectedDevices.remove(device.id)
                            } else {
                                selectedDevices.insert(device.id)
                            }
                        }
                    )
                }
                
                // Add selected button
                if !selectedDevices.isEmpty {
                    Button {
                        Haptics.impact(.medium)
                        addSelectedMiners()
                    } label: {
                        HStack(spacing: Spacing.sm) {
                            Image(systemName: "plus.circle.fill")
                            Text("Add \(selectedDevices.count) Miner\(selectedDevices.count == 1 ? "" : "s")")
                        }
                        .font(.bodyMedium)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.lg)
                        .background(
                            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                .fill(.teal)
                        )
                    }
                    .buttonStyle(PressableStyle())
                    .padding(.top, Spacing.md)
                }
            }
        }
    }
    
    // MARK: - Manual View
    
    private var manualView: some View {
        ScrollView {
            VStack(spacing: Spacing.xl) {
                // IP input card
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text("IP Address")
                        .font(.captionLarge)
                        .foregroundStyle(AppColors.textSecondary)
                    
                    TextField("192.168.1.100", text: $manualIP)
                        .font(.bodyLarge)
                        .fontDesign(.monospaced)
                        .keyboardType(.decimalPad)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .padding(Spacing.lg)
                        .background(
                            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                .fill(AppColors.fillTertiary)
                        )
                }
                .padding(Spacing.lg)
                .background(
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .fill(AppColors.backgroundGroupedSecondary)
                )
                
                // Error message
                if let error = errorMessage {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(AppColors.statusOffline)
                        
                        Text(error)
                            .font(.bodySmall)
                            .foregroundStyle(AppColors.statusOffline)
                    }
                    .padding(Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .fill(AppColors.statusOffline.opacity(0.1))
                    )
                }
                
                // Connect button
                Button {
                    Haptics.impact(.medium)
                    Task { await connectManually() }
                } label: {
                    Group {
                        if isConnecting {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("Connect")
                                .fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.lg)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .fill(isValidIP ? Color.teal : AppColors.fillSecondary)
                    )
                    .foregroundStyle(isValidIP ? .white : AppColors.textTertiary)
                }
                .buttonStyle(PressableStyle())
                .disabled(!isValidIP || isConnecting)
                
                // Help text
                Text("Enter the IP address of your miner. Supports both AxeOS (Bitaxe) and Avalon miners.")
                    .font(.captionLarge)
                    .foregroundStyle(AppColors.textTertiary)
                    .multilineTextAlignment(.center)
            }
            .padding()
        }
    }
    
    // MARK: - Validation
    
    private var isValidIP: Bool {
        let pattern = #"^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$"#
        return manualIP.range(of: pattern, options: .regularExpression) != nil
    }
    
    // MARK: - Functions
    
    private func detectNetworkRange() async {
        // Simple detection - use common subnet
        networkRange = "192.168.1.1 - 192.168.1.254"
    }
    
    private func startScan() async {
        isScanning = true
        discoveredDevices = []
        
        // Scan common IP range for both AxeOS and Avalon miners
        await withTaskGroup(of: DiscoveredDevice?.self) { group in
            for i in 1...254 {
                let ip = "192.168.1.\(i)"
                group.addTask {
                    // Try AxeOS first (HTTP API)
                    let axeOSClient = AxeOSClient(deviceIpAddress: ip, urlSession: self.session)
                    let axeOSResult = await axeOSClient.getSystemInfo()
                    
                    switch axeOSResult {
                    case .success(let info):
                        return DiscoveredDevice(ipAddress: ip, info: .axeOS(info))
                    case .failure:
                        // If AxeOS fails, try Avalon (TCP port 4028)
                        let avalonClient = AvalonClient(deviceIpAddress: ip, timeout: 3.0)
                        let avalonResult = await avalonClient.getDeviceInfo()
                        
                        switch avalonResult {
                        case .success(let info):
                            return DiscoveredDevice(ipAddress: ip, info: .avalon(info))
                        case .failure:
                            return nil
                        }
                    }
                }
            }
            
            for await result in group {
                if let device = result {
                    await MainActor.run {
                        discoveredDevices.append(device)
                        Haptics.impact(.light)
                    }
                }
            }
        }
        
        isScanning = false
        
        if !discoveredDevices.isEmpty {
            Haptics.notification(.success)
        }
    }
    
    private func connectManually() async {
        errorMessage = nil
        isConnecting = true
        
        // Try AxeOS first
        let axeOSClient = AxeOSClient(deviceIpAddress: manualIP, urlSession: session)
        let axeOSResult = await axeOSClient.getSystemInfo()
        
        switch axeOSResult {
        case .success(let info):
            addMiner(ip: manualIP, info: .axeOS(info))
            isConnecting = false
            return
        case .failure:
            // Try Avalon
            let avalonClient = AvalonClient(deviceIpAddress: manualIP, timeout: 5.0)
            let avalonResult = await avalonClient.getDeviceInfo()
            
            switch avalonResult {
            case .success(let info):
                addMiner(ip: manualIP, info: .avalon(info))
            case .failure:
                errorMessage = "Could not connect to miner. Please check the IP address and try again."
                Haptics.notification(.error)
            }
        }
        
        isConnecting = false
    }
    
    private func addMiner(ip: String, info: DiscoveredDeviceInfo) {
        // Check if already exists
        if existingMiners.contains(where: { $0.macAddress == info.uniqueId }) {
            errorMessage = "This miner is already added."
            return
        }
        
        switch info {
        case .axeOS(let axeOSInfo):
            let miner = MinerUpdate.createMiner(from: axeOSInfo, ipAddress: ip)
            let update = MinerUpdate.from(miner: miner, info: axeOSInfo)
            modelContext.insert(miner)
            modelContext.insert(update)
            
        case .avalon(let avalonInfo):
            let miner = MinerUpdate.createMiner(from: avalonInfo, ipAddress: ip)
            let update = MinerUpdate.from(miner: miner, info: avalonInfo)
            modelContext.insert(miner)
            modelContext.insert(update)
        }
        
        try? modelContext.save()
        Haptics.notification(.success)
        dismiss()
    }
    
    private func addSelectedMiners() {
        let devicesToAdd = filteredDevices.filter { selectedDevices.contains($0.id) }
        
        for device in devicesToAdd {
            // Skip if already exists
            guard !existingMiners.contains(where: { $0.macAddress == device.info.uniqueId }) else {
                continue
            }
            
            switch device.info {
            case .axeOS(let axeOSInfo):
                let miner = MinerUpdate.createMiner(from: axeOSInfo, ipAddress: device.ipAddress)
                let update = MinerUpdate.from(miner: miner, info: axeOSInfo)
                modelContext.insert(miner)
                modelContext.insert(update)
                
            case .avalon(let avalonInfo):
                let miner = MinerUpdate.createMiner(from: avalonInfo, ipAddress: device.ipAddress)
                let update = MinerUpdate.from(miner: miner, info: avalonInfo)
                modelContext.insert(miner)
                modelContext.insert(update)
            }
        }
        
        try? modelContext.save()
        Haptics.notification(.success)
        dismiss()
    }
}

// MARK: - Discovered Device Row

struct DiscoveredDeviceRow: View {
    let device: AddMinerView.DiscoveredDevice
    let isSelected: Bool
    let onToggle: () -> Void
    
    private var minerType: MinerType {
        device.info.minerType
    }
    
    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: Spacing.md) {
                // Selection checkbox
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(isSelected ? Color.teal : AppColors.fillSecondary, lineWidth: 2)
                        .frame(width: 24, height: 24)
                    
                    if isSelected {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.teal)
                            .frame(width: 24, height: 24)
                        
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                
                // Device icon
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(AppColors.fillTertiary)
                        .frame(width: 44, height: 44)
                    
                    Image(minerType.imageName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 32, height: 32)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                
                // Info
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(device.info.displayName)
                        .font(.bodyMedium)
                        .fontWeight(.medium)
                        .foregroundStyle(AppColors.textPrimary)
                    
                    HStack(spacing: Spacing.sm) {
                        Text(device.ipAddress)
                            .font(.captionLarge)
                            .foregroundStyle(AppColors.textTertiary)
                        
                        Text("•")
                            .foregroundStyle(AppColors.textQuaternary)
                        
                        Text(minerType.displayName)
                            .font(.captionLarge)
                            .foregroundStyle(AppColors.textTertiary)
                    }
                }
                
                Spacer()
            }
            .padding(Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(isSelected ? Color.teal.opacity(0.1) : AppColors.backgroundGroupedSecondary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .stroke(isSelected ? Color.teal : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    AddMinerView()
        .modelContainer(for: [Miner.self, MinerUpdate.self], inMemory: true)
}
