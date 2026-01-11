//
//  Miner+iOS.swift
//  HashMonitor
//
//  iOS-specific extensions for Miner model
//

import Foundation
import SwiftData
import HashRipperKit

extension Miner {
    /// Threshold for marking miner as offline
    static let offlineThreshold: Int = 3
    
    /// Whether miner is considered online
    var isOnline: Bool {
        consecutiveTimeoutErrors < Self.offlineThreshold
    }
    
    /// Gets the latest MinerUpdate for this miner
    func getLatestUpdate(from context: ModelContext) -> MinerUpdate? {
        let macAddress = self.macAddress
        var descriptor = FetchDescriptor<MinerUpdate>(
            predicate: #Predicate<MinerUpdate> { update in
                update.macAddress == macAddress
            },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
    
    /// Gets recent MinerUpdates for this miner within a time range
    func getUpdates(from context: ModelContext, since: Date) -> [MinerUpdate] {
        let macAddress = self.macAddress
        let startTimestamp = Int64(since.timeIntervalSince1970 * 1000)
        let descriptor = FetchDescriptor<MinerUpdate>(
            predicate: #Predicate<MinerUpdate> { update in
                update.macAddress == macAddress && update.timestamp >= startTimestamp
            },
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }
}

// MARK: - MinerUpdate Timestamp Helpers

extension MinerUpdate {
    /// Convert timestamp to Date
    var date: Date {
        Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000)
    }
}
