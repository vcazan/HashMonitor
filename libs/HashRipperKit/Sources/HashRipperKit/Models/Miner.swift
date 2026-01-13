//
//  Miner.swift
//  HashRipperKit
//
//  Shared cross-platform SwiftData model
//

import Foundation
import SwiftData

/// Protocol type for miner communication
public enum MinerProtocolType: String, Codable, Sendable {
    case axeOS = "axeos"       // HTTP REST API (Bitaxe, NerdQAxe)
    case cgminer = "cgminer"   // TCP API on port 4028 (Avalon)
    case unknown = "unknown"
}

@Model
public final class Miner {
    public var hostName: String
    public var ipAddress: String
    public var ASICModel: String
    public var boardVersion: String?
    public var deviceModel: String?

    @Attribute(.unique)
    public var macAddress: String

    /// Track consecutive timeout errors for offline detection
    public var consecutiveTimeoutErrors: Int = 0
    
    /// Threshold for marking miner as offline
    public static let offlineThreshold: Int = 3
    
    /// Protocol type for API communication (stored as raw string for SwiftData)
    public var protocolTypeRaw: String = MinerProtocolType.axeOS.rawValue
    
    /// Inverse relationship to MinerUpdate - cascade deletes all updates when miner is deleted
    @Relationship(deleteRule: .cascade, inverse: \MinerUpdate.miner)
    public var updates: [MinerUpdate]? = []

    public init(
        hostName: String,
        ipAddress: String,
        ASICModel: String,
        boardVersion: String? = nil,
        deviceModel: String? = nil,
        macAddress: String,
        protocolType: MinerProtocolType = .axeOS
    ) {
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

// MARK: - Computed Properties

public extension Miner {
    /// The protocol type used to communicate with this miner
    var protocolType: MinerProtocolType {
        get {
            MinerProtocolType(rawValue: protocolTypeRaw) ?? .axeOS
        }
        set {
            protocolTypeRaw = newValue.rawValue
        }
    }
    
    /// Whether this is an Avalon miner (uses CGMiner API)
    var isAvalonMiner: Bool {
        protocolType == .cgminer
    }
    
    /// Whether this is an AxeOS miner (Bitaxe, NerdQAxe)
    var isAxeOSMiner: Bool {
        protocolType == .axeOS
    }
    
    var minerType: MinerType {
        // If this is an Avalon miner, return that type
        if isAvalonMiner {
            return .Avalon
        }
        return MinerType.from(boardVersion: boardVersion, deviceModel: deviceModel)
    }
    
    var minerDeviceDisplayName: String {
        if isAvalonMiner {
            return deviceModel ?? "Avalon Miner"
        }
        return MinerType.displayName(boardVersion: boardVersion, deviceModel: deviceModel)
    }
    
    var isOffline: Bool {
        consecutiveTimeoutErrors >= Self.offlineThreshold
    }
    
    var qAxeMinerIdentifier: String? {
        guard minerType.deviceGenre == .nerdQAxe else {
            return nil
        }
        switch minerType {
        case .NerdQAxePlus: return "NerdQAxe+"
        case .NerdQAxePlusPlus: return "NerdQAxe++"
        case .NerdQX: return "NerdQX"
        default: return nil
        }
    }
}

