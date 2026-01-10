//
//  AddMinerView.swift
//  HashRipper-iOS
//
//  Combined view for adding miners via scan or IP address
//

import SwiftUI
import SwiftData
import HashRipperKit
import AxeOSClient

enum AddMinerTab: String, CaseIterable {
    case scan = "Scan Network"
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
                .padding()
                
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
            .navigationTitle("Add Miner")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert("Scan Error", isPresented: $showScanError) {
                Button("OK") { }
            } message: {
                Text(scanErrorMessage)
            }
            .alert("Miner Added", isPresented: $showManualSuccess) {
                Button("OK") {
                    ipAddress = ""
                }
            } message: {
                Text("Successfully connected to the miner")
            }
        }
    }
    
    // MARK: - Scan Content
    
    private var scanContent: some View {
        VStack(spacing: 16) {
            if isScanning {
                // Scanning state
                Spacer()
                
                ProgressView()
                    .scaleEffect(1.5)
                    .padding()
                
                Text("Scanning network...")
                    .font(.headline)
                
                if !scanProgress.isEmpty {
                    Text(scanProgress)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Button("Cancel") {
                    isScanning = false
                }
                .buttonStyle(.bordered)
                .padding()
                
            } else if foundDevices.isEmpty {
                // Empty state - ready to scan
                Spacer()
                
                Image(systemName: "wifi.router")
                    .font(.system(size: 64))
                    .foregroundStyle(.secondary)
                    .padding()
                
                Text("Find Miners")
                    .font(.title2.bold())
                
                Text("Scan your local network to automatically discover Bitcoin miners")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                
                Spacer()
                
                Button {
                    Task { await startScan() }
                } label: {
                    Label("Start Scan", systemImage: "magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding()
                
            } else {
                // Results
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        if newDevices.isEmpty {
                            Text("No new miners found")
                                .font(.headline)
                        } else {
                            Text("Found \(newDevices.count) new miner\(newDevices.count == 1 ? "" : "s")")
                                .font(.headline)
                        }
                        
                        Spacer()
                        
                        if alreadyAddedCount > 0 {
                            Text("\(alreadyAddedCount) already added")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                    
                    if newDevices.isEmpty {
                        // All miners already added
                        Spacer()
                        
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 48))
                            .foregroundStyle(.green)
                        
                        Text("All found miners are already in your list")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                        
                        Spacer()
                    } else {
                        // Show new devices
                        List {
                            ForEach(newDevices, id: \.info.macAddr) { device in
                                HStack(spacing: 12) {
                                    Image(MinerType.from(boardVersion: device.info.boardVersion, deviceModel: device.info.deviceModel).imageName)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: 40, height: 40)
                                        .background(Color(.systemGray6))
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(device.info.hostname)
                                            .font(.headline)
                                        Text(device.client.deviceIpAddress)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                }
                            }
                        }
                        .listStyle(.plain)
                    }
                }
                
                // Action buttons
                VStack(spacing: 12) {
                    if !newDevices.isEmpty {
                        Button {
                            addAllMiners()
                            dismiss()
                        } label: {
                            Label("Add \(newDevices.count) Miner\(newDevices.count == 1 ? "" : "s")", systemImage: "plus.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }
                    
                    Button {
                        foundDevices = []
                        Task { await startScan() }
                    } label: {
                        Label("Scan Again", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                .padding()
            }
        }
    }
    
    // MARK: - Manual Content
    
    private var manualContent: some View {
        Form {
            Section {
                TextField("IP Address", text: $ipAddress)
                    .textContentType(.URL)
                    .keyboardType(.decimalPad)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .focused($isIPFieldFocused)
            } header: {
                Text("Miner IP Address")
            } footer: {
                Text("Enter the IP address of your miner (e.g., 192.168.1.100)")
            }
            
            if let error = manualError {
                Section {
                    Label(error, systemImage: "wifi.slash")
                        .foregroundStyle(.orange)
                }
            }
            
            Section {
                Button {
                    Task { await addManualMiner() }
                } label: {
                    HStack {
                        Spacer()
                        if isAddingManually {
                            ProgressView()
                                .padding(.trailing, 8)
                        }
                        Text(isAddingManually ? "Connecting..." : "Add Miner")
                        Spacer()
                    }
                }
                .disabled(ipAddress.isEmpty || isAddingManually)
            }
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
            
            scanProgress = "Scanning \(myIpAddresses.first ?? "unknown")..."
            
            // Pass existing miner IPs to exclude them from scan
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
        
        // Validate IP format
        let ipPattern = #"^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$"#
        guard ipAddress.range(of: ipPattern, options: .regularExpression) != nil else {
            manualError = "Invalid IP address format"
            return
        }
        
        let client = AxeOSClient(
            deviceIpAddress: ipAddress,
            urlSession: .shared
        )
        
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
        
        if errorString.contains("timed out") || 
           errorString.contains("timeout") ||
           errorString.contains("could not connect") {
            return "Could not reach miner at \(ipAddress). Check the IP address and make sure the miner is powered on."
        }
        
        if errorString.contains("network") ||
           errorString.contains("internet") ||
           errorString.contains("offline") {
            return "Network connection issue. Make sure you're connected to the same network as your miner."
        }
        
        if errorString.contains("certificate") ||
           errorString.contains("ssl") ||
           errorString.contains("tls") {
            return "Could not reach miner at \(ipAddress). The device doesn't appear to be a compatible miner."
        }
        
        if errorString.contains("host") ||
           errorString.contains("resolve") {
            return "Could not find a device at \(ipAddress). Check the IP address is correct."
        }
        
        if errorString.contains("refused") {
            return "Connection refused. The device at \(ipAddress) is not accepting connections."
        }
        
        if errorString.contains("decode") ||
           errorString.contains("json") {
            return "Device found but it doesn't appear to be a compatible AxeOS miner."
        }
        
        return "Could not connect to miner at \(ipAddress). Verify the address and try again."
    }
}

// Make IPAddressCalculator accessible
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

// Get local IP address - works on iOS
func getMyIPAddress() -> [String] {
    var addresses: [String] = []
    
    var ifaddr: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&ifaddr) == 0 else { return addresses }
    guard let firstAddr = ifaddr else { return addresses }
    
    for ifptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
        let interface = ifptr.pointee
        let addrFamily = interface.ifa_addr.pointee.sa_family
        
        // Only IPv4
        if addrFamily == UInt8(AF_INET) {
            let name = String(cString: interface.ifa_name)
            
            // en0 is WiFi on iOS
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
