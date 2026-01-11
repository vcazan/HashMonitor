//
//  MinerUpdate+Factory.swift
//  HashMonitor
//
//  Factory methods for creating MinerUpdate from API responses
//

import Foundation
import HashRipperKit
import AxeOSClient

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
    
    /// Creates a Miner from AxeOSDeviceInfo (for new miner creation)
    static func createMiner(from info: AxeOSDeviceInfo, ipAddress: String) -> Miner {
        Miner(
            hostName: info.hostname.isEmpty ? "BitAxe" : info.hostname,
            ipAddress: ipAddress,
            ASICModel: info.ASICModel,
            boardVersion: info.boardVersion,
            deviceModel: info.deviceModel,
            macAddress: info.macAddr
        )
    }
}
