//
//  HashRipperKit.swift
//  HashRipperKit
//
//  Cross-platform shared code for HashRipper iOS and macOS apps
//

import Foundation
import SwiftData

// Re-export dependencies
@_exported import AxeOSClient

// MARK: - SwiftData Schema

/// All SwiftData models used by HashRipper
public var hashRipperSchema: [any PersistentModel.Type] {
    [
        Miner.self,
        MinerUpdate.self
    ]
}

/// Create a ModelContainer for HashRipper data
/// - Parameter inMemory: Whether to use in-memory storage (useful for previews/testing)
/// - Returns: Configured ModelContainer
public func createModelContainer(inMemory: Bool = false) throws -> ModelContainer {
    let schema = Schema(hashRipperSchema)
    let configuration = ModelConfiguration(
        schema: schema,
        isStoredInMemoryOnly: inMemory
    )
    return try ModelContainer(for: schema, configurations: [configuration])
}

