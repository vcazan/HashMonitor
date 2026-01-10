//
//  DeviceRefresher.swift
//  HashRipper
//
//  Created by Matt Sellars
//

import AxeOSClient
import Foundation
import SwiftData
import SwiftUI

typealias IPAddress = String

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
    func rescanDevicesStreaming() async {
        let database = self.database
        let lastUpdateLock = self.lastUpdateLock
        
        Task.detached {
            let isAlreadyScanning = Task { @MainActor in
                return self.isScanning
            }
            guard !(await isAlreadyScanning.value) else {
                print("Scan already in progress")
                return
            }

            Task { @MainActor in
                self.isScanning = true
            }
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
                try await AxeOSDevicesScanner.shared.executeSwarmScanV2(
                    knownMinerIps: knownMinerIps,
                    customSubnetIPs: customSubnetIPs
                ) { device in
                    Task {
                        let count = await collector.append(device)
                        print("Found device \(count): \(device.info.hostname) at \(device.client.deviceIpAddress)")
                    }
                }
                
                // Get collected devices
                let devicesToProcess = await collector.getDevices()
                
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
