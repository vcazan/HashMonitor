//
//  AppSettings.swift
//  HashRipper
//
//  Created by Matt Sellars
//

import Foundation
import Combine
import AppKit
import AxeOSClient

@Observable
class AppSettings {
    static let shared = AppSettings()
    
    private let userDefaults = UserDefaults.standard
    
    // MARK: - Appearance
    
    enum AppearanceMode: Int, CaseIterable {
        case system = 0
        case light = 1
        case dark = 2
        
        var displayName: String {
            switch self {
            case .system: return "System"
            case .light: return "Light"
            case .dark: return "Dark"
            }
        }
        
        var iconName: String {
            switch self {
            case .system: return "circle.lefthalf.filled"
            case .light: return "sun.max"
            case .dark: return "moon"
            }
        }
    }
    
    @ObservationIgnored
    private let appearanceModeKey = "appearanceMode"
    var appearanceMode: AppearanceMode {
        get {
            let rawValue = userDefaults.integer(forKey: appearanceModeKey)
            return AppearanceMode(rawValue: rawValue) ?? .system
        }
        set {
            userDefaults.set(newValue.rawValue, forKey: appearanceModeKey)
            applyAppearance(newValue)
        }
    }
    
    func applyAppearance(_ mode: AppearanceMode) {
        DispatchQueue.main.async {
            switch mode {
            case .system:
                NSApp.appearance = nil
            case .light:
                NSApp.appearance = NSAppearance(named: .aqua)
            case .dark:
                NSApp.appearance = NSAppearance(named: .darkAqua)
            }
        }
    }
    
    // MARK: - General Settings

    @ObservationIgnored
    private let customSubnetsKey = "customSubnets"
    var customSubnets: [String] {
        get {
            return userDefaults.stringArray(forKey: customSubnetsKey) ?? []
        }
        set {
            userDefaults.set(newValue, forKey: customSubnetsKey)
        }
    }

    @ObservationIgnored
    private let useAutoDetectedSubnetsKey = "useAutoDetectedSubnets"
    var useAutoDetectedSubnets: Bool {
        get {
            // Default to true if not set
            if userDefaults.object(forKey: useAutoDetectedSubnetsKey) == nil {
                return true
            }
            return userDefaults.bool(forKey: useAutoDetectedSubnetsKey)
        }
        set {
            userDefaults.set(newValue, forKey: useAutoDetectedSubnetsKey)
        }
    }

    @ObservationIgnored
    private let includePreReleasesKey = "includePreReleases"
    var includePreReleases: Bool {
        get {
            // Default to false if not set
            if userDefaults.object(forKey: includePreReleasesKey) == nil {
                return false
            }
            return userDefaults.bool(forKey: includePreReleasesKey)
        }
        set {
            userDefaults.set(newValue, forKey: includePreReleasesKey)
        }
    }
    
    // MARK: - Avalon Miner Support
    
    @ObservationIgnored
    private let scanForAvalonMinersKey = "scanForAvalonMiners"
    /// Whether to scan for Avalon miners on the network (uses CGMiner API on port 4028)
    var scanForAvalonMiners: Bool {
        get {
            // Default to true - scan for all miner types
            if userDefaults.object(forKey: scanForAvalonMinersKey) == nil {
                return true
            }
            return userDefaults.bool(forKey: scanForAvalonMinersKey)
        }
        set {
            userDefaults.set(newValue, forKey: scanForAvalonMinersKey)
        }
    }

    @ObservationIgnored
    private let refreshIntervalKey = "minerRefreshInterval"
    var minerRefreshInterval: TimeInterval {
        get {
            let interval = userDefaults.double(forKey: refreshIntervalKey)
            return interval > 0 ? interval : 10.0 // Default to 10 seconds
        }
        set {
            userDefaults.set(newValue, forKey: refreshIntervalKey)
        }
    }
    
    @ObservationIgnored
    private let backgroundPollingIntervalKey = "backgroundPollingInterval"
    var backgroundPollingInterval: TimeInterval {
        get {
            let interval = userDefaults.double(forKey: backgroundPollingIntervalKey)
            return interval > 0 ? interval : 30.0 // Default to 30 seconds
        }
        set {
            userDefaults.set(newValue, forKey: backgroundPollingIntervalKey)
        }
    }
    
    @ObservationIgnored
    private let focusedMinerRefreshIntervalKey = "focusedMinerRefreshInterval"
    /// Refresh interval when actively viewing a specific miner's details
    var focusedMinerRefreshInterval: TimeInterval {
        get {
            let interval = userDefaults.double(forKey: focusedMinerRefreshIntervalKey)
            return interval > 0 ? interval : 5.0 // Default to 5 seconds for active viewing
        }
        set {
            userDefaults.set(newValue, forKey: focusedMinerRefreshIntervalKey)
        }
    }

    @ObservationIgnored
    private let statusBarEnabledKey = "statusBarEnabled"
    var isStatusBarEnabled: Bool {
        get {
            // Default to true if not set
            if userDefaults.object(forKey: statusBarEnabledKey) == nil {
                return true
            }
            return userDefaults.bool(forKey: statusBarEnabledKey)
        }
        set {
            userDefaults.set(newValue, forKey: statusBarEnabledKey)
        }
    }

    @ObservationIgnored
    private let offlineThresholdKey = "offlineThreshold"
    var offlineThreshold: Int {
        get {
            let threshold = userDefaults.integer(forKey: offlineThresholdKey)
            // Default to 5, ensure it's within valid range (3-20)
            if threshold == 0 {
                return 5
            }
            return min(max(threshold, 3), 20)
        }
        set {
            // Clamp value to valid range
            let clampedValue = min(max(newValue, 3), 20)
            userDefaults.set(clampedValue, forKey: offlineThresholdKey)
        }
    }

    @ObservationIgnored
    private let usePersistentDeploymentsKey = "usePersistentDeployments"
    var usePersistentDeployments: Bool {
        get {
            // Default to true - new deployment system is stable
            if userDefaults.object(forKey: usePersistentDeploymentsKey) == nil {
                return true
            }
            return userDefaults.bool(forKey: usePersistentDeploymentsKey)
        }
        set {
            userDefaults.set(newValue, forKey: usePersistentDeploymentsKey)
        }
    }

    @ObservationIgnored
    private let websocketLogBufferSizeKey = "websocketLogBufferSize"
    var websocketLogBufferSize: Int {
        get {
            let size = userDefaults.integer(forKey: websocketLogBufferSizeKey)
            // Default to 1000, ensure it's within valid range (100-10000)
            if size == 0 {
                return 1000
            }
            return min(max(size, 100), 10000)
        }
        set {
            // Clamp value to valid range
            let clampedValue = min(max(newValue, 100), 10000)
            userDefaults.set(clampedValue, forKey: websocketLogBufferSizeKey)
        }
    }

    // MARK: - WatchDog Settings

    @ObservationIgnored
    private let poolCheckerEnabledKey = "poolCheckerEnabled"
    var isPoolCheckerEnabled: Bool {
        get {
            // Default to false - user must opt-in
            if userDefaults.object(forKey: poolCheckerEnabledKey) == nil {
                return false
            }
            return userDefaults.bool(forKey: poolCheckerEnabledKey)
        }
        set {
            userDefaults.set(newValue, forKey: poolCheckerEnabledKey)
            // Post notification so coordinator can react
            NotificationCenter.default.post(name: .poolCheckerSettingChanged, object: nil)
        }
    }

    @ObservationIgnored
    private let watchdogEnabledMinersKey = "watchdogEnabledMiners"
    var watchdogEnabledMiners: Set<String> {
        get {
            let array = userDefaults.stringArray(forKey: watchdogEnabledMinersKey) ?? []
            return Set(array)
        }
        set {
            userDefaults.set(Array(newValue), forKey: watchdogEnabledMinersKey)
        }
    }
    
    @ObservationIgnored
    private let watchdogGloballyEnabledKey = "watchdogGloballyEnabled"
    var isWatchdogGloballyEnabled: Bool {
        get {
            // Default to true if not set
            if userDefaults.object(forKey: watchdogGloballyEnabledKey) == nil {
                return true
            }
            return userDefaults.bool(forKey: watchdogGloballyEnabledKey)
        }
        set {
            userDefaults.set(newValue, forKey: watchdogGloballyEnabledKey)
        }
    }
    
    @ObservationIgnored
    private let watchdogNotificationsEnabledKey = "watchdogNotificationsEnabled"
    var areWatchdogNotificationsEnabled: Bool {
        get {
            // Default to true if not set
            if userDefaults.object(forKey: watchdogNotificationsEnabledKey) == nil {
                return true
            }
            return userDefaults.bool(forKey: watchdogNotificationsEnabledKey)
        }
        set {
            userDefaults.set(newValue, forKey: watchdogNotificationsEnabledKey)
        }
    }
    
    @ObservationIgnored
    private let notifyOnMinerOfflineKey = "notifyOnMinerOffline"
    var notifyOnMinerOffline: Bool {
        get {
            if userDefaults.object(forKey: notifyOnMinerOfflineKey) == nil {
                return true
            }
            return userDefaults.bool(forKey: notifyOnMinerOfflineKey)
        }
        set {
            userDefaults.set(newValue, forKey: notifyOnMinerOfflineKey)
        }
    }
    
    @ObservationIgnored
    private let notifyOnMinerRestartKey = "notifyOnMinerRestart"
    var notifyOnMinerRestart: Bool {
        get {
            if userDefaults.object(forKey: notifyOnMinerRestartKey) == nil {
                return true
            }
            return userDefaults.bool(forKey: notifyOnMinerRestartKey)
        }
        set {
            userDefaults.set(newValue, forKey: notifyOnMinerRestartKey)
        }
    }
    
    // MARK: - Advanced WatchDog Settings
    
    @ObservationIgnored
    private let watchdogAdvancedModeKey = "watchdogAdvancedMode"
    var isWatchdogAdvancedModeEnabled: Bool {
        get {
            return userDefaults.bool(forKey: watchdogAdvancedModeKey)
        }
        set {
            userDefaults.set(newValue, forKey: watchdogAdvancedModeKey)
        }
    }
    
    @ObservationIgnored
    private let watchdogRestartCooldownKey = "watchdogRestartCooldown"
    /// Time in seconds between restart attempts (default: 180 = 3 minutes)
    var watchdogRestartCooldown: Double {
        get {
            let value = userDefaults.double(forKey: watchdogRestartCooldownKey)
            return value > 0 ? value : 180
        }
        set {
            userDefaults.set(newValue, forKey: watchdogRestartCooldownKey)
        }
    }
    
    @ObservationIgnored
    private let watchdogCheckIntervalKey = "watchdogCheckInterval"
    /// Time in seconds between health checks for each miner (default: 30)
    var watchdogCheckInterval: Double {
        get {
            let value = userDefaults.double(forKey: watchdogCheckIntervalKey)
            return value > 0 ? value : 30
        }
        set {
            userDefaults.set(newValue, forKey: watchdogCheckIntervalKey)
        }
    }
    
    @ObservationIgnored
    private let watchdogLowPowerThresholdKey = "watchdogLowPowerThreshold"
    /// Power threshold in watts - below this triggers concern (default: 0.1)
    var watchdogLowPowerThreshold: Double {
        get {
            let value = userDefaults.double(forKey: watchdogLowPowerThresholdKey)
            return value > 0 ? value : 0.1
        }
        set {
            userDefaults.set(newValue, forKey: watchdogLowPowerThresholdKey)
        }
    }
    
    @ObservationIgnored
    private let watchdogConsecutiveUpdatesKey = "watchdogConsecutiveUpdates"
    /// Number of consecutive low power readings needed before restart (default: 3)
    var watchdogConsecutiveUpdates: Int {
        get {
            let value = userDefaults.integer(forKey: watchdogConsecutiveUpdatesKey)
            return value > 0 ? value : 3
        }
        set {
            userDefaults.set(newValue, forKey: watchdogConsecutiveUpdatesKey)
        }
    }
    
    @ObservationIgnored
    private let watchdogHashRateThresholdKey = "watchdogHashRateThreshold"
    /// Hash rate threshold in GH/s - below this is considered stalled (default: 1.0 GH/s)
    var watchdogHashRateThreshold: Double {
        get {
            let value = userDefaults.double(forKey: watchdogHashRateThresholdKey)
            return value > 0 ? value : 1.0 // Default to 1.0 GH/s
        }
        set {
            userDefaults.set(newValue, forKey: watchdogHashRateThresholdKey)
        }
    }
    
    @ObservationIgnored
    private let watchdogRequireBothConditionsKey = "watchdogRequireBothConditions"
    /// If true, both power AND hash rate must be below threshold. If false, either condition triggers restart.
    var watchdogRequireBothConditions: Bool {
        get {
            // Default to true (both conditions required) for safer operation
            if userDefaults.object(forKey: watchdogRequireBothConditionsKey) == nil {
                return true
            }
            return userDefaults.bool(forKey: watchdogRequireBothConditionsKey)
        }
        set {
            userDefaults.set(newValue, forKey: watchdogRequireBothConditionsKey)
        }
    }
    
    @ObservationIgnored
    private let watchdogCheckHashRateKey = "watchdogCheckHashRate"
    /// Whether to check hash rate as a trigger condition
    var watchdogCheckHashRate: Bool {
        get {
            if userDefaults.object(forKey: watchdogCheckHashRateKey) == nil {
                return true // Default enabled
            }
            return userDefaults.bool(forKey: watchdogCheckHashRateKey)
        }
        set {
            userDefaults.set(newValue, forKey: watchdogCheckHashRateKey)
        }
    }
    
    @ObservationIgnored
    private let watchdogCheckPowerKey = "watchdogCheckPower"
    /// Whether to check power as a trigger condition
    var watchdogCheckPower: Bool {
        get {
            if userDefaults.object(forKey: watchdogCheckPowerKey) == nil {
                return true // Default enabled
            }
            return userDefaults.bool(forKey: watchdogCheckPowerKey)
        }
        set {
            userDefaults.set(newValue, forKey: watchdogCheckPowerKey)
        }
    }
    
    // MARK: - Helper Methods
    
    func isWatchdogEnabled(for minerMacAddress: String) -> Bool {
        return isWatchdogGloballyEnabled && watchdogEnabledMiners.contains(minerMacAddress)
    }
    
    func enableWatchdog(for minerMacAddress: String) {
        watchdogEnabledMiners.insert(minerMacAddress)
    }
    
    func disableWatchdog(for minerMacAddress: String) {
        watchdogEnabledMiners.remove(minerMacAddress)
    }
    
    func enableWatchdogForAllMiners(_ macAddresses: [String]) {
        watchdogEnabledMiners = Set(macAddresses)
    }
    
    func disableWatchdogForAllMiners() {
        watchdogEnabledMiners.removeAll()
    }

    // MARK: - Subnet Helpers

    func addCustomSubnet(_ subnet: String) {
        var subnets = customSubnets
        if !subnets.contains(subnet) {
            subnets.append(subnet)
            customSubnets = subnets
        }
    }

    func removeCustomSubnet(_ subnet: String) {
        customSubnets = customSubnets.filter { $0 != subnet }
    }

    func getSubnetsToScan() -> [String] {
        var subnets: [String] = []

        // Add custom subnets if any are configured
        if !customSubnets.isEmpty {
            subnets.append(contentsOf: customSubnets)
        }

        // Add auto-detected subnets if enabled
        if useAutoDetectedSubnets {
            let autoDetectedIPs = getMyIPAddress()
            subnets.append(contentsOf: autoDetectedIPs)
        }

        // If no subnets configured, fall back to auto-detection
        if subnets.isEmpty {
            subnets = getMyIPAddress()
        }

        // Deduplicate based on subnet prefix (first 3 octets)
        return deduplicateSubnets(subnets)
    }

    private func deduplicateSubnets(_ ipAddresses: [String]) -> [String] {
        var seenSubnets = Set<String>()
        var uniqueIPs: [String] = []

        for ipAddress in ipAddresses {
            // Skip loopback addresses (127.x.x.x)
            if isLoopbackAddress(ipAddress) {
                continue
            }

            let subnetPrefix = getSubnetPrefix(ipAddress)
            if !seenSubnets.contains(subnetPrefix) {
                seenSubnets.insert(subnetPrefix)
                uniqueIPs.append(ipAddress)
            }
        }

        return uniqueIPs
    }

    private func getSubnetPrefix(_ ipAddress: String) -> String {
        let components = ipAddress.split(separator: ".")
        if components.count >= 3 {
            return "\(components[0]).\(components[1]).\(components[2])"
        }
        return ipAddress // Fallback for invalid IPs
    }

    private func isLoopbackAddress(_ ipAddress: String) -> Bool {
        return ipAddress.hasPrefix("127.")
    }

    private init() {
        // Private initializer for singleton
    }
}