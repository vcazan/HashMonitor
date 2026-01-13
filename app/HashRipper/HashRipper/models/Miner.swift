//
//  Miner.swift
//  HashRipper
//
//  Created by Matt Sellars
//

import SwiftData

/// Protocol type for miner communication
enum MinerProtocolType: String, Codable, Sendable {
    case axeOS = "axeos"       // HTTP REST API (Bitaxe, NerdQAxe)
    case cgminer = "cgminer"   // TCP API on port 4028 (Avalon)
    case unknown = "unknown"
}

@Model
final class Miner {
    public var hostName: String
    public var ipAddress: String
    public var ASICModel: String
    public var boardVersion: String?
    public var deviceModel: String?

    @Attribute(.unique)
    public var macAddress: String

    // Offline detection - track consecutive timeout errors
    public var consecutiveTimeoutErrors: Int = 0
    
    // Protocol type for API communication
    public var protocolTypeRaw: String = MinerProtocolType.axeOS.rawValue
    
    /// The protocol type used to communicate with this miner
    public var protocolType: MinerProtocolType {
        get {
            MinerProtocolType(rawValue: protocolTypeRaw) ?? .axeOS
        }
        set {
            protocolTypeRaw = newValue.rawValue
        }
    }
    
    /// Whether this is an Avalon miner (uses CGMiner API)
    public var isAvalonMiner: Bool {
        protocolType == .cgminer
    }
    
    /// Whether this is an AxeOS miner (Bitaxe, NerdQAxe)
    public var isAxeOSMiner: Bool {
        protocolType == .axeOS
    }

    public init(
        hostName: String,
        ipAddress: String,
        ASICModel: String,
        boardVersion: String? = nil,
        deviceModel: String? = nil,
        macAddress: String,
        protocolType: MinerProtocolType = .axeOS) {
        self.hostName = hostName
        self.ipAddress = ipAddress
        self.ASICModel = ASICModel
        self.boardVersion = boardVersion
        self.deviceModel = deviceModel
        self.macAddress = macAddress
        self.consecutiveTimeoutErrors = 0
        self.protocolTypeRaw = protocolType.rawValue
    }
}
