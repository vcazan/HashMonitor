//
//  MinerWatchDog.swift
//  HashRipper
//
//  Created by Matt Sellars
//

import AxeOSClient
import Foundation
import SwiftData

@Observable
class MinerWatchDog {
    // Default values (can be overridden by AppSettings)
    static let DEFAULT_RESTART_COOLDOWN: TimeInterval = 180 // 3 minutes
    static let DEFAULT_CHECK_INTERVAL: TimeInterval = 30 // 30 seconds
    static let DEFAULT_LOW_POWER_THRESHOLD: Double = 0.1 // watts
    static let DEFAULT_CONSECUTIVE_UPDATES: Int = 3
    
    // Get current settings
    private var restartCooldownInterval: TimeInterval {
        AppSettings.shared.watchdogRestartCooldown
    }
    private var checkThrottleInterval: TimeInterval {
        AppSettings.shared.watchdogCheckInterval
    }
    private var lowPowerThreshold: Double {
        AppSettings.shared.watchdogLowPowerThreshold
    }
    private var consecutiveUpdatesRequired: Int {
        AppSettings.shared.watchdogConsecutiveUpdates
    }
    private var hashRateThreshold: Double {
        AppSettings.shared.watchdogHashRateThreshold
    }
    
    // Track restart attempts to prevent multiple restarts
    private var minerRestartTimestamps: [String: Int64] = [:]
    // Track last check time to throttle frequent checks
    private var minerLastCheckTimestamps: [String: Int64] = [:]
    private let restartLock = UnfairLock()
    private let database: Database
    private weak var deploymentManager: FirmwareDeploymentManager?
    
    // Monitoring state
    private var isPaused: Bool = false
    private let pauseLock = UnfairLock()
    
    init(database: Database, deploymentManager: FirmwareDeploymentManager? = nil) {
        self.database = database
        self.deploymentManager = deploymentManager
        isPaused = false
    }
    
    func checkForRestartCondition(minerIpAddress: String) {
        // Check if monitoring is paused
        let monitoringPaused = pauseLock.perform { isPaused }
        guard !monitoringPaused else {
            return
        }

        // Check if WatchDog is globally enabled
        let settings = AppSettings.shared
        guard settings.isWatchdogGloballyEnabled else {
            return
        }

        // Throttle check frequency to prevent excessive database queries
        let currentTimestamp = Date().millisecondsSince1970
        let shouldSkipCheck = restartLock.perform {
            if let lastCheckTime = minerLastCheckTimestamps[minerIpAddress] {
                let timeSinceLastCheck = currentTimestamp - lastCheckTime
                return timeSinceLastCheck < Int64(self.checkThrottleInterval * 1000)
            }
            return false
        }

        guard !shouldSkipCheck else {
            return
        }

        // Update last check timestamp
        restartLock.perform {
            minerLastCheckTimestamps[minerIpAddress] = currentTimestamp
        }

        Task {
            // First check for active deployment outside database context
            let miner = await database.withModelContext { context -> Miner? in
                guard
                    let miners = try? context.fetch(FetchDescriptor<Miner>()),
                    let miner = miners.first(where: { $0.ipAddress == minerIpAddress})
                else { return nil }

                // Check if this specific miner is enabled for WatchDog monitoring
                guard settings.isWatchdogEnabled(for: miner.macAddress) else {
                    return nil
                }

                let monitoringPaused = self.pauseLock.perform { self.isPaused }
                guard !monitoringPaused else {
                    return nil
                }

                return miner
            }

            guard let miner = miner else { return }

            // Check for active deployment outside database context (MainActor isolated)
            let hasActiveDeployment = await checkForActiveDeployment(minerIpAddress: minerIpAddress)
            guard !hasActiveDeployment else {
                print("[MinerWatchDog] Skipping miner \(miner.hostName) (\(minerIpAddress)) - active firmware deployment")
                return
            }

            // Now do all the restart logic in a single database context
            let shouldRestart = await database.withModelContext { context -> Bool in
                guard
                    let miners = try? context.fetch(FetchDescriptor<Miner>()),
                    let miner = miners.first(where: { $0.ipAddress == minerIpAddress})
                else {
                    return false
                }

                // Get recent successful updates for this miner
                let recentUpdates = miner.getRecentUpdates(from: context, limit: 8)

                guard recentUpdates.count >= self.consecutiveUpdatesRequired else {
                    return false
                }

                let updates = Array(recentUpdates)
                let currentTimestamp = Date().millisecondsSince1970

                let lastRestartTime = self.restartLock.perform {
                    self.minerRestartTimestamps[minerIpAddress]
                }

                if let lastRestartTime = lastRestartTime {
                    let timeSinceRestart = currentTimestamp - lastRestartTime

                    // Check if miner has recovered (hashrate > 0) since restart
                    let hasRecovered = (updates.first?.hashRate ?? 0) > 0

                    if hasRecovered {
                        self.restartLock.perform {
                            self.minerRestartTimestamps.removeValue(forKey: minerIpAddress)
                        }
                        print("Miner \(miner.hostName) (\(minerIpAddress)) has recovered with hashrate \(updates.first?.hashRate ?? 0)")
                        return false
                    }

                    if timeSinceRestart < Int64(self.restartCooldownInterval * 1000) {
                        let remainingTime = Int64(self.restartCooldownInterval * 1000) - timeSinceRestart
                        print("Miner \(miner.hostName) (\(minerIpAddress)) restart cooldown active. Remaining: \(remainingTime/1000) seconds")
                        return false
                    } else {
                        // Check again if miner has recovered after cooldown period
                        let hasRecovered = (updates.first?.hashRate ?? 0) > 0

                        if hasRecovered {
                            self.restartLock.perform {
                                self.minerRestartTimestamps.removeValue(forKey: minerIpAddress)
                            }
                            print("Miner \(miner.hostName) (\(minerIpAddress)) has recovered with hashrate \(updates.first?.hashRate ?? 0)")
                            return false
                        }
                    }
                }

                // Check if all recent updates have power less than or equal to threshold
                let powerThreshold = self.lowPowerThreshold
                let allHaveLowPower = updates.allSatisfy { update in
                    return update.power <= powerThreshold
                }

                guard allHaveLowPower else {
                    print("[MinerWatchDog] Miner \(miner.hostName) (\(miner.ipAddress)) power levels healthy ✅")
                    return false
                }

                print("[MinerWatchDog] Miner \(miner.hostName) (\(miner.ipAddress)) unhealthy power levels detected ‼️")
                // Check if hashrate has not changed across these 3 updates
                let hashRates = updates.map { $0.hashRate }
                let firstHashRate = hashRates[0]
                let hashrateUnchanged = hashRates.allSatisfy { abs($0 - firstHashRate) < 0.001 }

                guard hashrateUnchanged else {
                    return false
                }

                print("Miner \(miner.hostName) (\(miner.ipAddress)) meets restart criteria: \(updates.count) consecutive updates with power <= 0.1 and unchanged hashrate (\(firstHashRate)). Issuing restart...")

                return true
            }

            // Issue restart outside of the model context if needed
            if shouldRestart {
                await issueRestart(to: miner.ipAddress, minerName: miner.hostName, minerMacAddress: miner.macAddress)
            }
        }
    }

    private func issueRestart(to minerIpAddress: String, minerName: String, minerMacAddress: String) async {
        // Record restart attempt
        restartLock.perform {
            minerRestartTimestamps[minerIpAddress] = Date().millisecondsSince1970
        }

        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 10.0
        sessionConfig.timeoutIntervalForResource = 10.0
        let session = URLSession(configuration: sessionConfig)
        let client = AxeOSClient(deviceIpAddress: minerIpAddress, urlSession: session)

        let result = await client.restartClient()
        switch result {
        case .success:
            print("Successfully issued restart command to miner \(minerName) (\(minerIpAddress))")
            // Update timestamp on successful restart
            restartLock.perform {
                minerRestartTimestamps[minerIpAddress] = Date().millisecondsSince1970
            }
            
            let reason = "Automatic restart due to low power (≤0.1W) and unchanged hashrate detected"
            
            // Log the successful restart action
            await logWatchdogAction(
                minerMacAddress: minerMacAddress,
                action: .restartMiner,
                reason: reason
            )
            
            // Send system notification
            await MainActor.run {
                WatchDogNotificationService.shared.notifyMinerRestarted(
                    minerName: minerName,
                    reason: reason
                )
            }

        case .failure(let error):
            print("Failed to restart miner \(minerName) (\(minerIpAddress)): \(error)")
            // Remove from tracking if restart failed so we can try again sooner
            restartLock.perform {
                minerRestartTimestamps.removeValue(forKey: minerIpAddress)
            }
        }
    }
    
    private func logWatchdogAction(minerMacAddress: String, action: Action, reason: String) async {
        await database.withModelContext { context in
            // Get the latest miner update to capture version information
            var latestUpdate: MinerUpdate?
            do {
                var descriptor = FetchDescriptor<MinerUpdate>(
                    predicate: #Predicate<MinerUpdate> { update in
                        update.macAddress == minerMacAddress && !update.isFailedUpdate
                    },
                    sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
                )
                descriptor.fetchLimit = 1
                latestUpdate = try context.fetch(descriptor).first
            } catch {
                print("Failed to fetch latest miner update for logging: \(error)")
            }
            
            let actionLog = WatchDogActionLog(
                minerMacAddress: minerMacAddress,
                action: action,
                reason: reason,
                timestamp: Date().millisecondsSince1970,
                isRead: false,
                minerFirmwareVersion: latestUpdate?.minerFirmwareVersion,
                axeOSVersion: latestUpdate?.axeOSVersion
            )
            context.insert(actionLog)
            
            do {
                try context.save()
                print("WatchDog action logged: \(action) for miner \(minerMacAddress) - firmware: \(latestUpdate?.minerFirmwareVersion ?? "unknown"), axeOS: \(latestUpdate?.axeOSVersion ?? "unknown")")
            } catch {
                print("Failed to save WatchDog action log: \(error)")
            }
        }
    }
    
    // Method to get current restart status for debugging/monitoring
    func getRestartStatus(for minerIpAddress: String) -> (isOnCooldown: Bool, remainingTime: TimeInterval?) {
        let cooldownInterval = restartCooldownInterval
        return restartLock.perform {
            guard let lastRestartTime = minerRestartTimestamps[minerIpAddress] else {
                return (false, nil)
            }
            
            let currentTimestamp = Date().millisecondsSince1970
            let timeSinceRestart = currentTimestamp - lastRestartTime
            let cooldownRemaining = Int64(cooldownInterval * 1000) - timeSinceRestart
            
            if cooldownRemaining > 0 {
                return (true, TimeInterval(cooldownRemaining / 1000))
            } else {
                return (false, nil)
            }
        }
    }
    
    // Method to manually clear restart tracking (for testing or admin purposes)
    func clearRestartTracking(for minerIpAddress: String) {
        restartLock.perform {
            minerRestartTimestamps.removeValue(forKey: minerIpAddress)
        }
        print("Cleared restart tracking for miner \(minerIpAddress)")
    }
    
    // Method to get all miners currently on cooldown
    func getMinersOnCooldown() -> [String] {
        let cooldownInterval = restartCooldownInterval
        return restartLock.perform {
            let currentTimestamp = Date().millisecondsSince1970
            return minerRestartTimestamps.compactMap { (ipAddress, lastRestartTime) in
                let timeSinceRestart = currentTimestamp - lastRestartTime
                let cooldownRemaining = Int64(cooldownInterval * 1000) - timeSinceRestart
                return cooldownRemaining > 0 ? ipAddress : nil
            }
        }
    }
    
    // MARK: - Monitoring Control
    
    func pauseMonitoring() {
        pauseLock.perform {
            isPaused = true
        }
        print("MinerWatchDog monitoring paused")
    }
    
    func resumeMonitoring() {
        pauseLock.perform {
            isPaused = false
        }
        print("MinerWatchDog monitoring resumed")
    }
    
    func isMonitoringPaused() -> Bool {
        return pauseLock.perform { isPaused }
    }
    
    // MARK: - Deployment Manager Integration
    
    func setDeploymentManager(_ deploymentManager: FirmwareDeploymentManager) {
        self.deploymentManager = deploymentManager
    }
    
    @MainActor
    private func checkForActiveDeployment(minerIpAddress: String) async -> Bool {
        guard let deploymentManager = deploymentManager else { return false }
        
        return deploymentManager.activeDeployments.contains { deployment in
            deployment.miner.ipAddress == minerIpAddress
        }
    }
}

