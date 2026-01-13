//
//  DeviceRefresher.swift
//  HashRipper
//
//  Created by Matt Sellars
//

import AxeOSClient
import AvalonClient
import Foundation
import SwiftData
import SwiftUI

typealias IPAddress = String

/// Result of scanning an IP address for miners
enum ScanResult: Sendable {
    case axeOS(DiscoveredDevice)
    case avalon(DiscoveredAvalonDevice)
    case none
}

@Observable
class NewMinerScanner {
    let database: Database
    var rescanInterval: TimeInterval = 300 // 5 min

    // Callback for when new miners are discovered
    var onNewMinersDiscovered: (([IPAddress]) -> Void)?

    let connectedDeviceUrlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 90
        config.waitsForConnectivity = false
        config.allowsCellularAccess = false
        config.allowsExpensiveNetworkAccess = false
        config.allowsConstrainedNetworkAccess = false
        return URLSession(configuration: config)
    }()

    private var rescanTimer: Timer?

    private let lastUpdateLock = UnfairLock()
    private var lastUpdate: Date?
    private(set) var isScanning: Bool = false
    private var isPaused: Bool = false

    init(database: Database) {
        self.database = database
    }

    func initializeDeviceScanner() {
        rescanTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true, block: { [self] _ in
            lastUpdateLock.perform(guardedTask: {
                guard !self.isPaused && !self.isScanning && (self.lastUpdate == nil || Date().timeIntervalSince(self.lastUpdate!) >= self.rescanInterval) else { return }
                Task {
                    await self.rescanDevicesStreaming()
                }
                self.lastUpdate = Date()
            })

        })
    }

    func pauseScanning() {
        isPaused = true
        print("📱 Miner scanning paused (app backgrounded) - ongoing scans will complete")
    }

    func resumeScanning() {
        isPaused = false
        print("📱 Miner scanning resumed (app foregrounded)")
    }

    func stopScanning() {
        isPaused = true
        rescanTimer?.invalidate()
        rescanTimer = nil
        print("📱 Miner scanning stopped")
    }

    func scanForNewMiner() async -> Result<NewDevice, Error>  {
        // new miner should only be at 192.168.4.1
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 10
        sessionConfig.waitsForConnectivity = false
        sessionConfig.allowsCellularAccess = false
        sessionConfig.allowsExpensiveNetworkAccess = false
        sessionConfig.allowsConstrainedNetworkAccess = false
        let session = URLSession(configuration: sessionConfig)
        let client = AxeOSClient(deviceIpAddress: "192.168.4.1", urlSession: session)
        let response = await client.getSystemInfo()
        switch response {
        case let .success(deviceInfo):
            return .success(NewDevice(client: client, clientInfo: deviceInfo))
        case .failure(let error):
            return .failure(error)
        }
    }

    func rescanDevices() async {
        let database = self.database
        let lastUpdateLock = self.lastUpdateLock
        
        Task.detached {
            print("Swarm scanning initiated")
            do {
                // Only extract IP addresses (Sendable) from the context
                let knownMinerIps: [String] = try await database.withModelContext({ modelContext in
                    let miners: [Miner] = try modelContext.fetch(FetchDescriptor())
                    return miners.map(\.ipAddress)
                })
                let customSubnetIPs = AppSettings.shared.getSubnetsToScan()
                print("🔍 Scanning subnets: \(customSubnetIPs)")
                let devices = try await AxeOSDevicesScanner.shared.executeSwarmScan(
                    knownMinerIps: knownMinerIps,
                    customSubnetIPs: customSubnetIPs
                )

                guard !devices.isEmpty else {
                    print("Swarm scan found no new devices")
                    return
                }

                print("Swarm scanning - model context created")

                // Process all devices in a single context - query miners fresh inside
                await database.withModelContext({ modelContext in
                    // Fetch miners fresh in this context
                    let allMiners: [Miner] = (try? modelContext.fetch(FetchDescriptor())) ?? []
                    let minersByIP = Dictionary(uniqueKeysWithValues: allMiners.map { ($0.ipAddress, $0) })
                    let minersByMAC = Dictionary(uniqueKeysWithValues: allMiners.map { ($0.macAddress, $0) })
                    
                    for device in devices {
                        let ipAddress = device.client.deviceIpAddress
                        let info = device.info

                        // Use freshly fetched miners for lookups
                        let existingIPMiner = minersByIP[ipAddress]
                        let existingMACMiner = minersByMAC[info.macAddr]

                        let miner: Miner
                        if let existing = existingIPMiner {
                            // IP already exists, update with current info
                            existing.hostName = info.hostname
                            existing.ASICModel = info.ASICModel
                            existing.boardVersion = info.boardVersion
                            existing.deviceModel = info.deviceModel
                            existing.macAddress = info.macAddr
                            miner = existing
                            print("Updated miner at existing IP \(ipAddress): \(miner.hostName)")
                        } else if let existing = existingMACMiner {
                            // MAC exists but IP is different - this miner changed IP
                            // Delete the old record and create new one (due to IP being unique)
                            modelContext.delete(existing)
                            miner = Miner(
                                hostName: info.hostname,
                                ipAddress: ipAddress,
                                ASICModel: info.ASICModel,
                                boardVersion: info.boardVersion,
                                deviceModel: info.deviceModel,
                                macAddress: info.macAddr
                            )
                            modelContext.insert(miner)
                            print("Miner \(info.hostname) changed IP from \(existing.ipAddress) to \(ipAddress)")
                        } else {
                            // Completely new miner
                            miner = Miner(
                                hostName: device.info.hostname,
                                ipAddress: ipAddress,
                                ASICModel: info.ASICModel,
                                boardVersion: info.boardVersion,
                                deviceModel: info.deviceModel,
                                macAddress: info.macAddr
                            )
                            modelContext.insert(miner)
                            print("Created new miner: \(miner.hostName)")
                        }

                        let minerUpdate = MinerUpdate(
                            miner: miner,
                            hostname: info.hostname,
                            stratumUser: info.stratumUser,
                            fallbackStratumUser: info.fallbackStratumUser,
                            stratumURL: info.stratumURL,
                            stratumPort: info.stratumPort,
                            fallbackStratumURL: info.fallbackStratumURL,
                            fallbackStratumPort: info.fallbackStratumPort,
                            minerFirmwareVersion: info.version,
                            bestDiff: info.bestDiff,
                            bestSessionDiff: info.bestSessionDiff,
                            frequency: info.frequency,
                            voltage: info.voltage,
                            coreVoltage: info.coreVoltage,
                            temp: info.temp,
                            vrTemp: info.vrTemp,
                            fanrpm: info.fanrpm,
                            fanspeed: info.fanspeed,
                            autofanspeed: info.autofanspeed,
                            flipscreen: info.flipscreen,
                            invertscreen: info.invertscreen,
                            invertfanpolarity: info.invertfanpolarity,
                            hashRate: info.hashRate ?? 0,
                            power: info.power ?? 0,
                            sharesAccepted: info.sharesAccepted,
                            sharesRejected: info.sharesRejected,
                            uptimeSeconds: info.uptimeSeconds,
                            isUsingFallbackStratum: info.isUsingFallbackStratum
                        )

                        modelContext.insert(minerUpdate)
                    }

                    do {
                        try modelContext.save()
                    } catch(let error) {
                        print("Failed to insert miner data: \(String(describing: error))")
                    }
                })
                await MainActor.run {
                    self.isScanning = false
                }
                lastUpdateLock.perform(guardedTask: {
                    self.lastUpdate = Date()
                })
            } catch (let error) {
                await MainActor.run {
                    self.isScanning = false
                }
                print("Failed to refresh devices: \(String(describing: error))")
                return
            }
        }
    }
    
    /// Scans for new devices using streaming results - devices are collected and processed in batch
    @MainActor
    func rescanDevicesStreaming() async {
        // Check and set isScanning on MainActor BEFORE spawning detached task
        // This ensures the caller can reliably poll isScanning
        guard !isScanning else {
            print("Scan already in progress")
            return
        }
        isScanning = true
        
        let database = self.database
        let lastUpdateLock = self.lastUpdateLock
        
        Task.detached {
            print("Streaming swarm scanning initiated")
            do {
                // Only extract IP addresses (Sendable) from the context
                let knownMinerIps: [String] = try await database.withModelContext({ modelContext in
                    let miners: [Miner] = try modelContext.fetch(FetchDescriptor())
                    return miners.map(\.ipAddress)
                })
                
                // Use actor to safely accumulate devices from concurrent callbacks
                actor DeviceCollector {
                    private var devices: [DiscoveredDevice] = []
                    func append(_ device: DiscoveredDevice) -> Int {
                        devices.append(device)
                        return devices.count
                    }
                    func getDevices() -> [DiscoveredDevice] { devices }
                }
                let collector = DeviceCollector()

                let customSubnetIPs = AppSettings.shared.getSubnetsToScan()
                print("🔍 Streaming scan using subnets: \(customSubnetIPs)")
                
                // Scan for AxeOS devices (Bitaxe, NerdQAxe)
                try await AxeOSDevicesScanner.shared.executeSwarmScanV2(
                    knownMinerIps: knownMinerIps,
                    customSubnetIPs: customSubnetIPs
                ) { device in
                    Task {
                        let count = await collector.append(device)
                        print("Found AxeOS device \(count): \(device.info.hostname) at \(device.client.deviceIpAddress)")
                    }
                }
                
                // Get collected AxeOS devices
                let devicesToProcess = await collector.getDevices()
                
                // Also scan for Avalon miners if enabled
                if AppSettings.shared.scanForAvalonMiners {
                    print("🔍 Also scanning for Avalon miners on port 4028...")
                    await self.scanForAvalonMinersInBackground(
                        knownMinerIps: knownMinerIps,
                        customSubnetIPs: customSubnetIPs,
                        database: database
                    )
                }
                
                // Process all devices in a single batch with fresh miner lookups
                let newMinerIpAddresses: [IPAddress] = await database.withModelContext({ modelContext -> [IPAddress] in
                    // Fetch miners fresh in this context
                    let allMiners: [Miner] = (try? modelContext.fetch(FetchDescriptor())) ?? []
                    let minersByIP = Dictionary(uniqueKeysWithValues: allMiners.map { ($0.ipAddress, $0) })
                    let minersByMAC = Dictionary(uniqueKeysWithValues: allMiners.map { ($0.macAddress, $0) })
                    
                    var newIpAddresses: [IPAddress] = []
                    
                    for device in devicesToProcess {
                            let ipAddress = device.client.deviceIpAddress
                            let info = device.info

                        // Use freshly fetched miners for lookups
                            let existingIPMiner = minersByIP[ipAddress]
                            let existingMACMiner = minersByMAC[info.macAddr]

                            let miner: Miner
                            if let existing = existingIPMiner {
                                // IP already exists, update with current info
                                existing.hostName = info.hostname
                                existing.ASICModel = info.ASICModel
                                existing.boardVersion = info.boardVersion
                                existing.deviceModel = info.deviceModel
                                existing.macAddress = info.macAddr
                                miner = existing
                                print("Updated miner at existing IP \(ipAddress): \(miner.hostName)")
                            } else if let existing = existingMACMiner {
                                // MAC exists but IP is different - this miner changed IP
                                // Delete the old record and create new one (due to IP being unique)
                                modelContext.delete(existing)
                                miner = Miner(
                                    hostName: info.hostname,
                                    ipAddress: ipAddress,
                                    ASICModel: info.ASICModel,
                                    boardVersion: info.boardVersion,
                                    deviceModel: info.deviceModel,
                                    macAddress: info.macAddr
                                )
                                modelContext.insert(miner)
                                print("Miner \(info.hostname) changed IP from \(existing.ipAddress) to \(ipAddress)")
                            } else {
                                // Completely new miner
                                miner = Miner(
                                    hostName: device.info.hostname,
                                    ipAddress: ipAddress,
                                    ASICModel: info.ASICModel,
                                    boardVersion: info.boardVersion,
                                    deviceModel: info.deviceModel,
                                    macAddress: info.macAddr
                                )
                                modelContext.insert(miner)

                                // Track this new IP address for callback
                            newIpAddresses.append(ipAddress)
                                print("Created new miner: \(miner.hostName)")
                            }

                            let minerUpdate = MinerUpdate(
                                miner: miner,
                                hostname: info.hostname,
                                stratumUser: info.stratumUser,
                                fallbackStratumUser: info.fallbackStratumUser,
                                stratumURL: info.stratumURL,
                                stratumPort: info.stratumPort,
                                fallbackStratumURL: info.fallbackStratumURL,
                                fallbackStratumPort: info.fallbackStratumPort,
                                minerFirmwareVersion: info.version,
                                axeOSVersion: info.axeOSVersion,
                                bestDiff: info.bestDiff,
                                bestSessionDiff: info.bestSessionDiff,
                                frequency: info.frequency,
                                voltage: info.voltage,
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

                            modelContext.insert(minerUpdate)
                    }

                            do {
                                try modelContext.save()
                        print("Successfully saved \(devicesToProcess.count) miner updates")
                            } catch(let error) {
                        print("Failed to save miner data: \(String(describing: error))")
                    }
                    
                    return newIpAddresses
                })
                
                print("Streaming swarm scan completed - found \(devicesToProcess.count) devices")
                
                // Notify about newly discovered miners
                if !newMinerIpAddresses.isEmpty {
                    await MainActor.run {
                        self.onNewMinersDiscovered?(newMinerIpAddresses)
                    }
                }
                
                await MainActor.run {
                    self.isScanning = false
                }
                lastUpdateLock.perform(guardedTask: {
                    self.lastUpdate = Date()
                })
            } catch (let error) {
                await MainActor.run {
                    self.isScanning = false
                }
                print("Failed to refresh devices with streaming scan: \(String(describing: error))")
                return
            }
        }
    }
    
    // MARK: - Avalon Miner Scanning
    
    /// Scan for Avalon miners on the network using CGMiner API (port 4028)
    private func scanForAvalonMinersInBackground(
        knownMinerIps: [String],
        customSubnetIPs: [String],
        database: Database
    ) async {
        var subnetsToScan: [String] = []
        if !customSubnetIPs.isEmpty {
            subnetsToScan = customSubnetIPs
        } else {
            subnetsToScan = getMyIPAddress()
        }
        
        // Generate IP addresses to scan (same logic as AxeOS scanner)
        var ipAddressesToCheck: [String] = []
        for subnetIP in subnetsToScan {
            let ipAddresses = calculateIpRange(ip: subnetIP)?.filter { 
                $0 != subnetIP && !knownMinerIps.contains($0)
            } ?? []
            ipAddressesToCheck.append(contentsOf: ipAddresses)
        }
        
        // Scan for Avalon miners concurrently
        await withTaskGroup(of: Void.self) { group in
            for ipAddress in ipAddressesToCheck {
                group.addTask { @Sendable [database] in
                    let client = AvalonClient(deviceIpAddress: ipAddress, timeout: 3.0)
                    let result = await client.getDeviceInfo()
                    
                    if case .success(let info) = result {
                        print("🔍 Found Avalon miner at \(ipAddress): \(info.deviceModel)")
                        await self.processDiscoveredAvalonMiner(
                            ipAddress: ipAddress,
                            info: info,
                            database: database
                        )
                    }
                }
            }
        }
    }
    
    /// Process a discovered Avalon miner and add it to the database
    @MainActor
    private func processDiscoveredAvalonMiner(
        ipAddress: String,
        info: AvalonDeviceInfo,
        database: Database
    ) async {
        await database.withModelContext { modelContext in
            let allMiners: [Miner] = (try? modelContext.fetch(FetchDescriptor())) ?? []
            
            // Check for existing miner by IP or MAC
            let existingIPMiner = allMiners.first { $0.ipAddress == ipAddress }
            let existingMACMiner = !info.macAddr.isEmpty ? allMiners.first { $0.macAddress == info.macAddr } : nil
            
            let miner: Miner
            if let existing = existingIPMiner {
                // Update existing miner
                existing.hostName = info.hostname
                existing.ASICModel = info.deviceModel
                existing.deviceModel = info.deviceModel
                existing.protocolType = .cgminer
                miner = existing
                print("Updated Avalon miner at \(ipAddress): \(miner.hostName)")
            } else if let existing = existingMACMiner {
                // MAC exists but IP changed
                modelContext.delete(existing)
                miner = Miner(
                    hostName: info.hostname,
                    ipAddress: ipAddress,
                    ASICModel: info.deviceModel,
                    deviceModel: info.deviceModel,
                    macAddress: info.macAddr.isEmpty ? UUID().uuidString : info.macAddr,
                    protocolType: .cgminer
                )
                modelContext.insert(miner)
                print("Avalon miner \(info.hostname) changed IP to \(ipAddress)")
            } else {
                // New miner
                miner = Miner(
                    hostName: info.hostname,
                    ipAddress: ipAddress,
                    ASICModel: info.deviceModel,
                    deviceModel: info.deviceModel,
                    macAddress: info.macAddr.isEmpty ? UUID().uuidString : info.macAddr,
                    protocolType: .cgminer
                )
                modelContext.insert(miner)
                print("Created new Avalon miner: \(miner.hostName) at \(ipAddress)")
            }
            
            // Create a MinerUpdate record for the Avalon miner
            // Note: hashRate from AvalonDeviceInfo is already in GH/s, matching MinerUpdate's expected unit
            let minerUpdate = MinerUpdate(
                miner: miner,
                hostname: info.hostname,
                stratumUser: info.stratumUser,
                fallbackStratumUser: "",
                stratumURL: info.stratumURL,
                stratumPort: info.stratumPort,
                fallbackStratumURL: "",
                fallbackStratumPort: 0,
                minerFirmwareVersion: info.firmwareVersion,
                bestDiff: info.bestDiff,
                frequency: info.frequency,
                voltage: info.voltage,
                temp: info.temperature,
                intakeTemp: info.intakeTemp,
                chipTempMax: info.chipTempMax,
                chipTempMin: info.chipTempMin,
                fanrpm: info.fanSpeed,
                fanspeed: Double(info.fanSpeedPercent),
                hashRate: info.hashRate,  // Already in GH/s
                power: info.power,
                sharesAccepted: info.sharesAccepted,
                sharesRejected: info.sharesRejected,
                uptimeSeconds: info.uptimeSeconds,
                isUsingFallbackStratum: false
            )
            
            modelContext.insert(minerUpdate)
            
            do {
                try modelContext.save()
            } catch {
                print("Failed to save Avalon miner: \(error)")
            }
        }
        
        // Notify about newly discovered miner
        onNewMinersDiscovered?([ipAddress])
    }
}

extension EnvironmentValues {
    @Entry var newMinerScanner: NewMinerScanner? = nil
}

extension Scene {
  func newMinerScanner(_ c: NewMinerScanner) -> some Scene {
    environment(\.newMinerScanner, c)
  }
}

extension View {
  func newMinerScanner(_ c: NewMinerScanner) -> some View {
    environment(\.newMinerScanner, c)
  }
}

struct NewDevice {
    let client: AxeOSClient
    let clientInfo: AxeOSDeviceInfo
}

// MARK: - IP Address Utilities for Avalon Scanning

/// Calculate IP range for a given subnet (used for Avalon miner scanning)
private func calculateIpRange(ip: String, netmask: String = "255.255.255.0") -> [String]? {
    guard let ipInt = ipToInt(ip), let netmaskInt = ipToInt(netmask) else { return nil }
    
    let network = ipInt & netmaskInt
    let broadcast = network | ~netmaskInt
    
    var ipAddresses: [String] = []
    for current in (network + 1)...(broadcast - 1) {
        ipAddresses.append(intToIp(current))
    }
    return ipAddresses
}

private func ipToInt(_ ip: String) -> UInt32? {
    let parts = ip.split(separator: ".")
    guard parts.count == 4 else { return nil }
    
    var ipInt: UInt32 = 0
    for part in parts {
        guard let octet = UInt32(part) else { return nil }
        ipInt = (ipInt << 8) | octet
    }
    return ipInt
}

private func intToIp(_ ipInt: UInt32) -> String {
    let a = (ipInt >> 24) & 0xFF
    let b = (ipInt >> 16) & 0xFF
    let c = (ipInt >> 8) & 0xFF
    let d = ipInt & 0xFF
    return "\(a).\(b).\(c).\(d)"
}
