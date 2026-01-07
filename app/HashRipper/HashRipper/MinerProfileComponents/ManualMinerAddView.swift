//
//  ManualMinerAddView.swift
//  HashRipper
//
//  Created for manual miner addition by IP address
//

import SwiftUI
import SwiftData
import AxeOSClient

/// View for manually adding a miner by IP address
/// Useful when network scanning doesn't discover a miner
struct ManualMinerAddView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.database) private var database
    @Environment(\.minerClientManager) private var minerClientManager
    
    @State private var ipAddress: String = ""
    @State private var isConnecting: Bool = false
    @State private var connectionError: String? = nil
    @State private var discoveredDevice: AxeOSDeviceInfo? = nil
    @State private var showSuccessAlert: Bool = false
    
    var onDismiss: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "network")
                    .font(.system(size: 40))
                    .foregroundStyle(.blue)
                VStack(alignment: .leading) {
                    Text("Add Miner Manually")
                        .font(.title2)
                        .bold()
                    Text("Enter the IP address of an AxeOS-based miner")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding()
            
            Divider()
            
            // Content
            VStack(spacing: 24) {
                // IP Address Input
                VStack(alignment: .leading, spacing: 8) {
                    Text("Miner IP Address")
                        .font(.headline)
                    
                    HStack {
                        TextField("e.g., 192.168.1.100", text: $ipAddress)
                            .textFieldStyle(.roundedBorder)
                            .disabled(isConnecting)
                            .onSubmit {
                                if isValidIPAddress {
                                    connectToMiner()
                                }
                            }
                        
                        Button(action: connectToMiner) {
                            if isConnecting {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .frame(width: 16, height: 16)
                            } else {
                                Text("Connect")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!isValidIPAddress || isConnecting)
                    }
                    
                    if !ipAddress.isEmpty && !isValidIPAddress {
                        Text("Please enter a valid IP address (e.g., 192.168.1.100)")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                
                // Connection Status / Error
                if let error = connectionError {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(error)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(8)
                }
                
                // Discovered Device Info
                if let device = discoveredDevice {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.title2)
                            Text("Miner Found!")
                                .font(.headline)
                                .foregroundStyle(.green)
                        }
                        
                        Divider()
                        
                        DeviceInfoRow(label: "Hostname", value: device.hostname)
                        DeviceInfoRow(label: "Device", value: device.minerDeviceDisplayName)
                        DeviceInfoRow(label: "ASIC Model", value: device.ASICModel)
                        DeviceInfoRow(label: "Firmware", value: device.version)
                        if let axeOSVersion = device.axeOSVersion {
                            DeviceInfoRow(label: "AxeOS", value: axeOSVersion)
                        }
                        DeviceInfoRow(label: "MAC Address", value: device.macAddr)
                        
                        if let hashRate = device.hashRate {
                            DeviceInfoRow(label: "Hash Rate", value: formatHashRate(hashRate))
                        }
                    }
                    .padding()
                    .background(Color.green.opacity(0.05))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.green.opacity(0.3), lineWidth: 1)
                    )
                }
                
                Spacer()
            }
            .padding()
            
            Divider()
            
            // Footer buttons
            HStack {
                Button("Cancel") {
                    onDismiss()
                }
                .keyboardShortcut(.cancelAction)
                
                Spacer()
                
                if discoveredDevice != nil {
                    Button("Add Miner") {
                        addMinerToDatabase()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding()
        }
        .frame(width: 500, height: discoveredDevice != nil ? 550 : 350)
        .alert("Miner Added", isPresented: $showSuccessAlert) {
            Button("OK") {
                onDismiss()
            }
        } message: {
            Text("The miner has been added and will now be monitored.")
        }
    }
    
    // MARK: - Validation
    
    private var isValidIPAddress: Bool {
        let trimmed = ipAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        
        let parts = trimmed.split(separator: ".")
        guard parts.count == 4 else { return false }
        
        for part in parts {
            guard let num = Int(part), num >= 0 && num <= 255 else {
                return false
            }
        }
        return true
    }
    
    // MARK: - Actions
    
    private func connectToMiner() {
        let trimmedIP = ipAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        
        isConnecting = true
        connectionError = nil
        discoveredDevice = nil
        
        Task {
            let sessionConfig = URLSessionConfiguration.default
            sessionConfig.timeoutIntervalForRequest = 10
            sessionConfig.waitsForConnectivity = false
            let session = URLSession(configuration: sessionConfig)
            
            let client = AxeOSClient(deviceIpAddress: trimmedIP, urlSession: session)
            let result = await client.getSystemInfo()
            
            await MainActor.run {
                isConnecting = false
                
                switch result {
                case .success(let deviceInfo):
                    discoveredDevice = deviceInfo
                    connectionError = nil
                    
                case .failure(let error):
                    discoveredDevice = nil
                    let nsError = error as NSError
                    
                    switch nsError.code {
                    case -1001:
                        connectionError = "Connection timed out. Make sure the miner is powered on and the IP address is correct."
                    case -1004:
                        connectionError = "Could not connect to miner. The device may be offline or the IP address may be incorrect."
                    case -1003:
                        connectionError = "Host not found. Please check the IP address."
                    default:
                        connectionError = "Failed to connect: \(error.localizedDescription)"
                    }
                }
            }
        }
    }
    
    private func addMinerToDatabase() {
        guard let deviceInfo = discoveredDevice else { return }
        
        let trimmedIP = ipAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        
        Task {
            await database.withModelContext { context in
                // Check if miner already exists by MAC address
                let macAddress = deviceInfo.macAddr
                let existingMiners = try? context.fetch(FetchDescriptor<Miner>())
                
                if let existing = existingMiners?.first(where: { $0.macAddress == macAddress }) {
                    // Update existing miner's IP if it changed
                    if existing.ipAddress != trimmedIP {
                        existing.ipAddress = trimmedIP
                        existing.hostName = deviceInfo.hostname
                        print("Updated existing miner \(existing.hostName) with new IP: \(trimmedIP)")
                    }
                } else if let existingByIP = existingMiners?.first(where: { $0.ipAddress == trimmedIP }) {
                    // IP exists but different MAC - update the record
                    existingByIP.macAddress = macAddress
                    existingByIP.hostName = deviceInfo.hostname
                    existingByIP.ASICModel = deviceInfo.ASICModel
                    existingByIP.boardVersion = deviceInfo.boardVersion
                    existingByIP.deviceModel = deviceInfo.deviceModel
                    print("Updated miner at IP \(trimmedIP) with new MAC: \(macAddress)")
                } else {
                    // Create new miner
                    let newMiner = Miner(
                        hostName: deviceInfo.hostname,
                        ipAddress: trimmedIP,
                        ASICModel: deviceInfo.ASICModel,
                        boardVersion: deviceInfo.boardVersion,
                        deviceModel: deviceInfo.deviceModel,
                        macAddress: macAddress
                    )
                    context.insert(newMiner)
                    
                    // Create initial update record
                    let minerUpdate = MinerUpdate(
                        miner: newMiner,
                        hostname: deviceInfo.hostname,
                        stratumUser: deviceInfo.stratumUser,
                        fallbackStratumUser: deviceInfo.fallbackStratumUser,
                        stratumURL: deviceInfo.stratumURL,
                        stratumPort: deviceInfo.stratumPort,
                        fallbackStratumURL: deviceInfo.fallbackStratumURL,
                        fallbackStratumPort: deviceInfo.fallbackStratumPort,
                        minerFirmwareVersion: deviceInfo.version,
                        axeOSVersion: deviceInfo.axeOSVersion,
                        bestDiff: deviceInfo.bestDiff,
                        bestSessionDiff: deviceInfo.bestSessionDiff,
                        frequency: deviceInfo.frequency,
                        voltage: deviceInfo.voltage,
                        temp: deviceInfo.temp,
                        vrTemp: deviceInfo.vrTemp,
                        fanrpm: deviceInfo.fanrpm,
                        fanspeed: deviceInfo.fanspeed,
                        hashRate: deviceInfo.hashRate ?? 0,
                        power: deviceInfo.power ?? 0,
                        sharesAccepted: deviceInfo.sharesAccepted,
                        sharesRejected: deviceInfo.sharesRejected,
                        uptimeSeconds: deviceInfo.uptimeSeconds,
                        isUsingFallbackStratum: deviceInfo.isUsingFallbackStratum
                    )
                    context.insert(minerUpdate)
                    print("Created new miner: \(newMiner.hostName) at \(trimmedIP)")
                }
                
                do {
                    try context.save()
                } catch {
                    print("Failed to save miner: \(error)")
                }
            }
            
            // Notify the client manager to set up refresh scheduler for this miner
            await MainActor.run {
                minerClientManager?.handleNewlyDiscoveredMiners([trimmedIP])
                showSuccessAlert = true
            }
        }
    }
    
    // MARK: - Helpers
    
    private func formatHashRate(_ hashRate: Double) -> String {
        if hashRate >= 1000 {
            return String(format: "%.2f TH/s", hashRate / 1000)
        } else {
            return String(format: "%.2f GH/s", hashRate)
        }
    }
}

// MARK: - Helper Views

private struct DeviceInfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .leading)
            Text(value)
                .fontWeight(.medium)
            Spacer()
        }
        .font(.callout)
    }
}

#Preview {
    ManualMinerAddView(onDismiss: {})
}

