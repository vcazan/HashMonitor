//
//  MinerUpdate+Factory.swift
//  HashMonitor
//
//  Factory methods for creating MinerUpdate from API responses
//

import Foundation
import HashRipperKit
import AxeOSClient
import AvalonClient

extension MinerUpdate {
    /// Creates a MinerUpdate from AxeOSDeviceInfo API response
    static func from(miner: Miner, info: AxeOSDeviceInfo) -> MinerUpdate {
        MinerUpdate(
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
            isUsingFallbackStratum: info.isUsingFallbackStratum,
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            isFailedUpdate: false
        )
    }
    
    /// Creates a MinerUpdate from AvalonDeviceInfo API response
    static func from(miner: Miner, info: AvalonDeviceInfo) -> MinerUpdate {
        MinerUpdate(
            miner: miner,
            hostname: info.hostname,
            stratumUser: info.stratumUser,
            fallbackStratumUser: "",
            stratumURL: info.stratumURL,
            stratumPort: info.stratumPort,
            fallbackStratumURL: "",
            fallbackStratumPort: 0,
            minerFirmwareVersion: info.firmwareVersion,
            axeOSVersion: nil,
            bestDiff: info.bestDiff,
            bestSessionDiff: nil,
            frequency: info.frequency,
            voltage: info.voltage,
            coreVoltage: nil,
            temp: info.temperature,           // TAvg - average chip temp
            vrTemp: info.chipTempMax,         // Use vrTemp to store TMax for display
            intakeTemp: info.intakeTemp,      // ITemp - intake temperature
            chipTempMax: info.chipTempMax,    // TMax - max chip temperature
            chipTempMin: info.chipTempMin,    // TMin - min chip temperature
            fanrpm: info.fanSpeed,
            fanspeed: Double(info.fanSpeedPercent),
            autofanspeed: nil,
            flipscreen: nil,
            invertscreen: nil,
            invertfanpolarity: nil,
            hashRate: info.hashRate,          // Already in GH/s
            power: info.power,
            sharesAccepted: info.sharesAccepted,
            sharesRejected: info.sharesRejected,
            uptimeSeconds: info.uptimeSeconds,
            isUsingFallbackStratum: false,
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            isFailedUpdate: false
        )
    }
    
    /// Creates a Miner from AxeOSDeviceInfo (for new miner creation)
    static func createMiner(from info: AxeOSDeviceInfo, ipAddress: String) -> Miner {
        Miner(
            hostName: info.hostname.isEmpty ? "BitAxe" : info.hostname,
            ipAddress: ipAddress,
            ASICModel: info.ASICModel,
            boardVersion: info.boardVersion,
            deviceModel: info.deviceModel,
            macAddress: info.macAddr,
            protocolType: .axeOS
        )
    }
    
    /// Creates a Miner from AvalonDeviceInfo (for new miner creation)
    static func createMiner(from info: AvalonDeviceInfo, ipAddress: String) -> Miner {
        // Generate a unique identifier for Avalon miners (they don't have MAC addresses in the API)
        let uniqueId = "avalon-\(ipAddress.replacingOccurrences(of: ".", with: "-"))"
        
        return Miner(
            hostName: info.hostname.isEmpty ? "Avalon" : info.hostname,
            ipAddress: ipAddress,
            ASICModel: info.deviceModel,
            boardVersion: nil,
            deviceModel: info.deviceModel,
            macAddress: uniqueId,  // Use IP-based unique ID since MAC not available
            protocolType: .cgminer
        )
    }
}
