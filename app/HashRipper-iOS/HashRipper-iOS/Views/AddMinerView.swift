//
//  AddMinerView.swift
//  HashRipper-iOS
//
//  Professional miner addition view with muted design
//

import SwiftUI
import SwiftData
import HashRipperKit
import AxeOSClient

enum AddMinerTab: String, CaseIterable {
    case scan = "Scan"
    case manual = "Enter IP"
}

struct AddMinerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Miner.hostName) private var existingMiners: [Miner]
    
    @State private var selectedTab: AddMinerTab = .scan
    
    // Scan state
    @State private var isScanning = false
    @State private var scanProgress: String = ""
    @State private var foundDevices: [DiscoveredDevice] = []
    @State private var showScanError = false
    @State private var scanErrorMessage = ""
    
    // Manual add state
    @State private var ipAddress = ""
    @State private var isAddingManually = false
    @State private var manualError: String?
    @State private var showManualSuccess = false
    
    @FocusState private var isIPFieldFocused: Bool
    
    // Filter out already added miners
    private var newDevices: [DiscoveredDevice] {
        let existingMacs = Set(existingMiners.map { $0.macAddress })
        return foundDevices.filter { !existingMacs.contains($0.info.macAddr) }
    }
    
    private var alreadyAddedCount: Int {
        foundDevices.count - newDevices.count
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Tab picker
                Picker("Add Method", selection: $selectedTab) {
                    ForEach(AddMinerTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                
                Divider()
                
                // Content based on selected tab
                Group {
                    switch selectedTab {
                    case .scan:
                        scanContent
                    case .manual:
                        manualContent
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Add Miner")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(AppColors.accent)
                }
            }
            .alert("Scan Error", isPresented: $showScanError) {
                Button("OK") { }
            } message: {
                Text(scanErrorMessage)
            }
            .alert("Miner Added", isPresented: $showManualSuccess) {
                Button("OK") { ipAddress = "" }
            } message: {
                Text("Successfully connected to the miner")
            }
        }
    }
    
    // MARK: - Scan Content
    
    private var scanContent: some View {
        VStack(spacing: 0) {
            if isScanning {
                scanningView
            } else if foundDevices.isEmpty {
                emptyStateView
            } else {
                resultsView
            }
        }
    }
    
    private var scanningView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            ZStack {
                Circle()
                    .stroke(AppColors.accent.opacity(0.2), lineWidth: 3)
                    .frame(width: 80, height: 80)
                
                ProgressView()
                    .scaleEffect(1.3)
                    .tint(AppColors.accent)
            }
            
            VStack(spacing: 6) {
                Text("Scanning Network")
                    .font(.system(size: 18, weight: .semibold))
                
                if !scanProgress.isEmpty {
                    Text(scanProgress)
                        .font(.system(size: 13))
                        .foregroundStyle(AppColors.subtleText)
                        .animation(.easeInOut, value: scanProgress)
                }
            }
            
            Spacer()
            
            Button("Cancel") {
                isScanning = false
            }
            .buttonStyle(.bordered)
            .tint(AppColors.subtleText)
            .controlSize(.large)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: "wifi.router")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(AppColors.mutedText)
            
            VStack(spacing: 8) {
                Text("Find Miners")
                    .font(.system(size: 20, weight: .semibold))
                
                Text("Scan your local network to discover\nAxeOS-based Bitcoin miners")
                    .font(.system(size: 14))
                    .foregroundStyle(AppColors.subtleText)
                    .multilineTextAlignment(.center)
            }
            
            Spacer()
            
            Button {
                Task { await startScan() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                    Text("Start Scan")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppColors.accent)
            .controlSize(.large)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity)
    }
    
    private var resultsView: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                if newDevices.isEmpty {
                    Text("No new miners")
                        .font(.system(size: 15, weight: .semibold))
                } else {
                    Text("\(newDevices.count) new miner\(newDevices.count == 1 ? "" : "s")")
                        .font(.system(size: 15, weight: .semibold))
                }
                
                Spacer()
                
                if alreadyAddedCount > 0 {
                    Text("\(alreadyAddedCount) already added")
                        .font(.system(size: 12))
                        .foregroundStyle(AppColors.mutedText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.tertiarySystemFill))
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            
            Divider()
            
            if newDevices.isEmpty {
                allAddedView
            } else {
                devicesList
            }
            
            // Action buttons
            VStack(spacing: 10) {
                if !newDevices.isEmpty {
                    Button {
                        addAllMiners()
                        dismiss()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus.circle.fill")
                            Text("Add \(newDevices.count) Miner\(newDevices.count == 1 ? "" : "s")")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppColors.accent)
                    .controlSize(.large)
                }
                
                Button {
                    foundDevices = []
                    Task { await startScan() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.clockwise")
                        Text("Scan Again")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(AppColors.subtleText)
                .controlSize(.large)
            }
            .padding(16)
            .background(Color(.systemGroupedBackground))
        }
    }
    
    private var allAddedView: some View {
        VStack(spacing: 16) {
            Spacer()
            
            Image(systemName: "checkmark.circle")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(AppColors.success)
            
            VStack(spacing: 4) {
                Text("All Set")
                    .font(.system(size: 17, weight: .semibold))
                
                Text("All discovered miners are already in your list")
                    .font(.system(size: 14))
                    .foregroundStyle(AppColors.subtleText)
                    .multilineTextAlignment(.center)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
    }
    
    private var devicesList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(newDevices, id: \.info.macAddr) { device in
                    DiscoveredMinerRow(device: device)
                    
                    if device.info.macAddr != newDevices.last?.info.macAddr {
                        Divider()
                            .padding(.leading, 68)
                    }
                }
            }
            .background(AppColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(AppColors.cardBorder, lineWidth: 0.5)
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }
    
    // MARK: - Manual Content
    
    private var manualContent: some View {
        ScrollView {
            VStack(spacing: 20) {
                // IP Input Card
                VStack(alignment: .leading, spacing: 12) {
                    Text("Miner IP Address")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppColors.subtleText)
                    
                    TextField("192.168.1.100", text: $ipAddress)
                        .textContentType(.URL)
                        .keyboardType(.decimalPad)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .focused($isIPFieldFocused)
                        .font(.system(size: 17, weight: .medium, design: .monospaced))
                        .padding(14)
                        .background(Color(.tertiarySystemFill))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    
                    Text("Enter the IP address of your AxeOS miner")
                        .font(.system(size: 12))
                        .foregroundStyle(AppColors.mutedText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .cardStyle()
                
                // Error message
                if let error = manualError {
                    HStack(spacing: 10) {
                        Image(systemName: "wifi.slash")
                            .font(.system(size: 16))
                            .foregroundStyle(AppColors.warning)
                        
                        Text(error)
                            .font(.system(size: 13))
                            .foregroundStyle(AppColors.warning)
                        
                        Spacer()
                    }
                    .padding(14)
                    .background(AppColors.warningLight)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                
                // Add button
                Button {
                    Task { await addManualMiner() }
                } label: {
                    HStack(spacing: 8) {
                        if isAddingManually {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "plus.circle.fill")
                        }
                        Text(isAddingManually ? "Connecting..." : "Add Miner")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppColors.accent)
                .controlSize(.large)
                .disabled(ipAddress.isEmpty || isAddingManually)
                
                Spacer()
            }
            .padding(16)
        }
        .onAppear {
            if selectedTab == .manual {
                isIPFieldFocused = true
            }
        }
        .onChange(of: selectedTab) { _, newTab in
            if newTab == .manual {
                isIPFieldFocused = true
            }
        }
    }
    
    // MARK: - Scan Actions
    
    private func startScan() async {
        isScanning = true
        foundDevices = []
        scanProgress = "Getting network info..."
        
        do {
            let myIpAddresses = getMyIPAddress()
            
            guard !myIpAddresses.isEmpty else {
                await MainActor.run {
                    scanErrorMessage = "Could not determine your network address. Make sure you're connected to WiFi."
                    showScanError = true
                    isScanning = false
                }
                return
            }
            
            scanProgress = "Scanning \(myIpAddresses.first ?? "network")..."
            
            let existingIPs = existingMiners.map { $0.ipAddress }
            
            try await AxeOSDevicesScanner.shared.executeSwarmScanV2(
                knownMinerIps: existingIPs,
                customSubnetIPs: myIpAddresses
            ) { device in
                Task { @MainActor in
                    if !foundDevices.contains(where: { $0.info.macAddr == device.info.macAddr }) {
                        foundDevices.append(device)
                        scanProgress = "Found: \(device.info.hostname)"
                    }
                }
            }
            
            await MainActor.run {
                isScanning = false
                scanProgress = ""
            }
            
        } catch {
            await MainActor.run {
                scanErrorMessage = "Scan failed: \(error.localizedDescription)"
                showScanError = true
                isScanning = false
            }
        }
    }
    
    private func addAllMiners() {
        for device in newDevices {
            let info = device.info
            let ipAddress = device.client.deviceIpAddress
            
            let miner = Miner(
                hostName: info.hostname,
                ipAddress: ipAddress,
                ASICModel: info.ASICModel ?? "Unknown",
                boardVersion: info.boardVersion,
                deviceModel: info.deviceModel,
                macAddress: info.macAddr
            )
            modelContext.insert(miner)
            
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
        }
        
        do {
            try modelContext.save()
        } catch {
            print("Error saving miners: \(error)")
        }
    }
    
    // MARK: - Manual Add Actions
    
    private func addManualMiner() async {
        isAddingManually = true
        manualError = nil
        
        defer { isAddingManually = false }
        
        let ipPattern = #"^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$"#
        guard ipAddress.range(of: ipPattern, options: .regularExpression) != nil else {
            manualError = "Invalid IP address format"
            return
        }
        
        let client = AxeOSClient(deviceIpAddress: ipAddress, urlSession: .shared)
        let result = await client.getSystemInfo()
        
        switch result {
        case .success(let info):
            let macAddr = info.macAddr
            let descriptor = FetchDescriptor<Miner>(
                predicate: #Predicate<Miner> { $0.macAddress == macAddr }
            )
            
            if let existingMiner = try? modelContext.fetch(descriptor).first {
                existingMiner.ipAddress = ipAddress
                existingMiner.consecutiveTimeoutErrors = 0
                showManualSuccess = true
            } else {
                let miner = Miner(
                    hostName: info.hostname,
                    ipAddress: ipAddress,
                    ASICModel: info.ASICModel ?? "Unknown",
                    boardVersion: info.boardVersion,
                    deviceModel: info.deviceModel,
                    macAddress: macAddr
                )
                modelContext.insert(miner)
                showManualSuccess = true
            }
            
        case .failure(let error):
            manualError = friendlyErrorMessage(for: error)
        }
    }
    
    private func friendlyErrorMessage(for error: Error) -> String {
        let errorString = error.localizedDescription.lowercased()
        
        if errorString.contains("timed out") || errorString.contains("timeout") || errorString.contains("could not connect") {
            return "Could not reach miner. Check the IP and ensure it's powered on."
        }
        
        if errorString.contains("network") || errorString.contains("internet") || errorString.contains("offline") {
            return "Network issue. Ensure you're on the same network as the miner."
        }
        
        if errorString.contains("certificate") || errorString.contains("ssl") || errorString.contains("tls") {
            return "Device doesn't appear to be a compatible miner."
        }
        
        if errorString.contains("host") || errorString.contains("resolve") {
            return "Could not find a device at this IP address."
        }
        
        if errorString.contains("refused") {
            return "Connection refused. Device is not accepting connections."
        }
        
        if errorString.contains("decode") || errorString.contains("json") {
            return "Device found but isn't a compatible AxeOS miner."
        }
        
        return "Could not connect. Verify the address and try again."
    }
}

// MARK: - Supporting Views

struct DiscoveredMinerRow: View {
    let device: DiscoveredDevice
    
    var body: some View {
        HStack(spacing: 14) {
            Image(MinerType.from(boardVersion: device.info.boardVersion, deviceModel: device.info.deviceModel).imageName)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 40, height: 40)
                .background(Color(.tertiarySystemFill))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            
            VStack(alignment: .leading, spacing: 3) {
                Text(device.info.hostname)
                    .font(.system(size: 15, weight: .medium))
                
                Text(device.client.deviceIpAddress)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(AppColors.subtleText)
            }
            
            Spacer()
            
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(AppColors.success)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

// MARK: - IP Address Helpers

struct IPAddressCalculator {
    func ipToInt(_ ip: String) -> UInt32? {
        let parts = ip.split(separator: ".")
        guard parts.count == 4 else { return nil }
        
        var ipInt: UInt32 = 0
        for part in parts {
            guard let octet = UInt32(part) else { return nil }
            ipInt = (ipInt << 8) | octet
        }
        return ipInt
    }
    
    func intToIp(_ ipInt: UInt32) -> String {
        let a = (ipInt >> 24) & 0xFF
        let b = (ipInt >> 16) & 0xFF
        let c = (ipInt >> 8) & 0xFF
        let d = ipInt & 0xFF
        return "\(a).\(b).\(c).\(d)"
    }
    
    func calculateIpRange(ip: String, netmask: String = "255.255.255.0") -> [String]? {
        guard let ipInt = ipToInt(ip), let netmaskInt = ipToInt(netmask) else { return nil }
        
        let network = ipInt & netmaskInt
        let broadcast = network | ~netmaskInt
        
        var ipAddresses: [String] = []
        for current in (network + 1)...(broadcast - 1) {
            ipAddresses.append(intToIp(current))
        }
        return ipAddresses
    }
}

func getMyIPAddress() -> [String] {
    var addresses: [String] = []
    
    var ifaddr: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&ifaddr) == 0 else { return addresses }
    guard let firstAddr = ifaddr else { return addresses }
    
    for ifptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
        let interface = ifptr.pointee
        let addrFamily = interface.ifa_addr.pointee.sa_family
        
        if addrFamily == UInt8(AF_INET) {
            let name = String(cString: interface.ifa_name)
            
            if name == "en0" || name == "en1" {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                           &hostname, socklen_t(hostname.count),
                           nil, socklen_t(0), NI_NUMERICHOST)
                let address = String(cString: hostname)
                
                if address.split(separator: ".").count == 4 {
                    addresses.append(address)
                }
            }
        }
    }
    freeifaddrs(ifaddr)
    
    return addresses
}

#Preview {
    AddMinerView()
        .modelContainer(try! createModelContainer(inMemory: true))
}
