//
//  MinerUpdateCleanupService.swift
//  HashRipper
//
//  Created by Matt Sellars
//

import Foundation
import SwiftData

/// Efficient cleanup service for MinerUpdate records that runs batched operations in the background
/// Now uses time-based retention (30 days) instead of count-based
actor MinerUpdateCleanupService {
    private let database: Database
    private var cleanupTask: Task<Void, Never>?
    private var lastCleanupTime: Date = Date()

    // Cleanup configuration - time-based retention
    private let retentionDays: Int = 30 // Keep 30 days of history
    private let cleanupInterval: TimeInterval = 3600 // Run cleanup every hour (less frequently since time-based)
    private let batchSize = 1000 // Process more records per batch since we're less frequent

    init(database: Database) {
        self.database = database
    }

    func startCleanupService() {
        guard cleanupTask == nil else { return }

        cleanupTask = Task { [weak self] in
            await self?.cleanupLoop()
        }
    }

    func stopCleanupService() {
        cleanupTask?.cancel()
        cleanupTask = nil
    }

    /// Trigger immediate cleanup check (called when a miner reaches threshold)
    func triggerCleanupCheck() {
        // Only trigger if enough time has passed since last cleanup
        let timeSinceLastCleanup = Date().timeIntervalSince(lastCleanupTime)
        if timeSinceLastCleanup > 60 { // Minimum 1 minute between cleanups
            Task {
                await performBatchedCleanup()
            }
        }
    }

    private func cleanupLoop() async {
        while !Task.isCancelled {
            do {
                // Wait for cleanup interval
                try await Task.sleep(nanoseconds: UInt64(cleanupInterval * 1_000_000_000))

                if !Task.isCancelled {
                    await performBatchedCleanup()
                }
            } catch {
                // Task was cancelled or interrupted
                break
            }
        }
    }

    private func performBatchedCleanup() async {
        print("🧹 Starting time-based MinerUpdate cleanup (retention: \(retentionDays) days)...")
        lastCleanupTime = Date()

        do {
            // Create a dedicated context for cleanup
            let modelContainer = SharedDatabase.shared.modelContainer
            let context = ModelContext(modelContainer)

            // Calculate cutoff timestamp (30 days ago in milliseconds)
            let cutoffDate = Calendar.current.date(byAdding: .day, value: -retentionDays, to: Date()) ?? Date()
            let cutoffTimestamp = Int64(cutoffDate.timeIntervalSince1970 * 1000)

            // Delete all records older than retention period
            let totalDeleted = try deleteOldRecordsSync(cutoffTimestamp: cutoffTimestamp, context: context)

            // Save all changes at the end
            try context.save()

            if totalDeleted > 0 {
                print("✅ Cleanup completed: deleted \(totalDeleted) records older than \(retentionDays) days")
            } else {
                print("✅ Cleanup completed: no records needed deletion")
            }

        } catch {
            print("❌ Error during time-based cleanup: \(error)")
        }
    }

    nonisolated private func deleteOldRecordsSync(cutoffTimestamp: Int64, context: ModelContext) throws -> Int {
        // Fetch records older than cutoff in batches
        var oldRecordsDescriptor = FetchDescriptor<MinerUpdate>(
            predicate: #Predicate<MinerUpdate> { update in
                update.timestamp < cutoffTimestamp
            },
            sortBy: [SortDescriptor(\MinerUpdate.timestamp, order: .forward)]
        )
        oldRecordsDescriptor.fetchLimit = batchSize

        var totalDeleted = 0
        
        // Delete in batches until no more old records
        while true {
            let oldRecords = try context.fetch(oldRecordsDescriptor)
            
            if oldRecords.isEmpty { break }
            
            for record in oldRecords {
                context.delete(record)
                totalDeleted += 1
            }
            
            // Save periodically to avoid memory pressure
            if totalDeleted % batchSize == 0 {
                try context.save()
            }
        }

        return totalDeleted
    }

    /// Clean up orphaned MinerUpdate records that have broken miner relationships
    func cleanupOrphanedUpdates() async {
        print("🔍 Checking for orphaned MinerUpdate records...")

        do {
            let modelContainer = SharedDatabase.shared.modelContainer
            let context = ModelContext(modelContainer)

            // Get all MinerUpdate records
            let allUpdates = try context.fetch(FetchDescriptor<MinerUpdate>())
            var orphanedCount = 0

            // Fetch all current miner MAC addresses to identify orphans
            let minerDescriptor = FetchDescriptor<Miner>()
            let allMiners = try context.fetch(minerDescriptor)
            let validMacAddresses = Set(allMiners.map { $0.macAddress })

            for update in allUpdates {
                // Check if this update's miner still exists by comparing MAC addresses
                // We can't safely access update.miner if the relationship is broken
                if !validMacAddresses.contains(update.macAddress) {
                    print("🧹 Deleting orphaned MinerUpdate for non-existent miner \(update.macAddress)")
                    context.delete(update)
                    orphanedCount += 1
                }
            }

            if orphanedCount > 0 {
                try context.save()
                print("✅ Cleaned up \(orphanedCount) orphaned MinerUpdate records")
            } else {
                print("✅ No orphaned MinerUpdate records found")
            }

        } catch {
            print("❌ Error cleaning up orphaned updates: \(error)")
        }
    }
}

// Helper extension for batching arrays
extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
