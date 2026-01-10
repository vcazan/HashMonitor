//
//  MinerUpdate.swift
//  HashRipperKit
//
//  Shared cross-platform SwiftData model
//

import Foundation
import SwiftData

@Model
public final class MinerUpdate {
    public var hostname: String
    public var stratumUser: String
    public var fallbackStratumUser: String
    public var stratumURL: String
    public var stratumPort: Int
    public var fallbackStratumURL: String
    public var fallbackStratumPort: Int
    public var minerFirmwareVersion: String
    public var axeOSVersion: String?
    public var bestDiff: String?
    public var bestSessionDiff: String?
    public var frequency: Double?
    public var voltage: Double?
    public var coreVoltage: Int?
    public var temp: Double?
    public var vrTemp: Double?
    public var fanrpm: Int?
    public var fanspeed: Double?
    public var autofanspeed: Int?
    public var flipscreen: Int?
    public var invertscreen: Int?
    public var invertfanpolarity: Int?
    public var hashRate: Double
    public var power: Double
    public var sharesAccepted: Int?
    public var sharesRejected: Int?
    public var uptimeSeconds: Int?
    public var isUsingFallbackStratum: Bool
    public var miner: Miner
    public var macAddress: String
    public var timestamp: Int64
    public var isFailedUpdate: Bool

    public init(
        miner: Miner,
        hostname: String,
        stratumUser: String,
        fallbackStratumUser: String,
        stratumURL: String,
        stratumPort: Int,
        fallbackStratumURL: String,
        fallbackStratumPort: Int,
        minerFirmwareVersion: String,
        axeOSVersion: String? = nil,
        bestDiff: String? = nil,
        bestSessionDiff: String? = nil,
        frequency: Double? = nil,
        voltage: Double? = nil,
        coreVoltage: Int? = nil,
        temp: Double? = nil,
        vrTemp: Double? = nil,
        fanrpm: Int? = nil,
        fanspeed: Double? = nil,
        autofanspeed: Int? = nil,
        flipscreen: Int? = nil,
        invertscreen: Int? = nil,
        invertfanpolarity: Int? = nil,
        hashRate: Double,
        power: Double,
        sharesAccepted: Int? = nil,
        sharesRejected: Int? = nil,
        uptimeSeconds: Int? = nil,
        isUsingFallbackStratum: Bool,
        timestamp: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        isFailedUpdate: Bool = false
    ) {
        self.miner = miner
        self.macAddress = miner.macAddress
        self.hostname = hostname
        self.stratumUser = stratumUser
        self.fallbackStratumUser = fallbackStratumUser
        self.stratumURL = stratumURL
        self.stratumPort = stratumPort
        self.fallbackStratumURL = fallbackStratumURL
        self.fallbackStratumPort = fallbackStratumPort
        self.minerFirmwareVersion = minerFirmwareVersion
        self.axeOSVersion = axeOSVersion
        self.bestDiff = bestDiff?.replacingOccurrences(of: " ", with: "")
        self.bestSessionDiff = bestSessionDiff?.replacingOccurrences(of: " ", with: "")
        self.frequency = frequency
        self.voltage = voltage
        self.coreVoltage = coreVoltage
        self.temp = temp
        self.vrTemp = vrTemp
        self.fanrpm = fanrpm
        self.fanspeed = fanspeed
        self.autofanspeed = autofanspeed
        self.flipscreen = flipscreen
        self.invertscreen = invertscreen
        self.invertfanpolarity = invertfanpolarity
        self.hashRate = hashRate
        self.power = power
        self.sharesAccepted = sharesAccepted
        self.sharesRejected = sharesRejected
        self.uptimeSeconds = uptimeSeconds
        self.isUsingFallbackStratum = isUsingFallbackStratum
        self.timestamp = timestamp
        self.isFailedUpdate = isFailedUpdate
    }
}

