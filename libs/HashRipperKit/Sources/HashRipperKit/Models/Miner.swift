//
//  Miner.swift
//  HashRipperKit
//
//  Shared cross-platform SwiftData model
//

import Foundation
import SwiftData

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
    
    /// Inverse relationship to MinerUpdate - cascade deletes all updates when miner is deleted
    @Relationship(deleteRule: .cascade, inverse: \MinerUpdate.miner)
    public var updates: [MinerUpdate]? = []

    public init(
        hostName: String,
        ipAddress: String,
        ASICModel: String,
        boardVersion: String? = nil,
        deviceModel: String? = nil,
        macAddress: String
    ) {
        self.hostName = hostName
        self.ipAddress = ipAddress
        self.ASICModel = ASICModel
        self.boardVersion = boardVersion
        self.deviceModel = deviceModel
        self.macAddress = macAddress
        self.consecutiveTimeoutErrors = 0
    }
}

// MARK: - Computed Properties

public extension Miner {
    var minerType: MinerType {
        MinerType.from(boardVersion: boardVersion, deviceModel: deviceModel)
    }
    
    var minerDeviceDisplayName: String {
        MinerType.displayName(boardVersion: boardVersion, deviceModel: deviceModel)
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

