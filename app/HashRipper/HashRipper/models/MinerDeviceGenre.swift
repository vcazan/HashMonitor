//
//  MinerDeviceGenre.swift
//  HashRipper
//
//  Created by Matt Sellars
//

import Foundation

enum MinerDeviceGenre: CaseIterable, Sendable {
    case bitaxe
    case nerdQAxe
    case avalon
    case unknown
    
    var name: String {
        switch self {
        case .bitaxe:
            return "Bitaxe OS Devices"
        case .nerdQAxe:
            return "NerdQAxe OS Devices"
        case .avalon:
            return "Avalon Miners"
        case .unknown:
            return "Unknown"
        }
    }
    
    /// Whether this device genre uses the AxeOS HTTP API
    var usesAxeOSAPI: Bool {
        switch self {
        case .bitaxe, .nerdQAxe:
            return true
        case .avalon, .unknown:
            return false
        }
    }
    
    /// Whether this device genre uses the CGMiner TCP API (port 4028)
    var usesCGMinerAPI: Bool {
        switch self {
        case .avalon:
            return true
        case .bitaxe, .nerdQAxe, .unknown:
            return false
        }
    }
    
    var firmareUpdateUrlString: String? {
        switch self {
        case .bitaxe:
            return "https://api.github.com/repos/bitaxeorg/esp-miner/releases"
        case .nerdQAxe:
            return "https://api.github.com/repos/shufps/esp-miner-nerdqaxeplus/releases"
        case .avalon:
            // Avalon firmware is managed differently - typically through Canaan's official channels
            return nil
        case .unknown:
            return nil
        }
    }
    
    var firmwareUpdateUrl: URL? {
        guard let string = firmareUpdateUrlString else {
            return nil
        }

        return URL(string: string)
    }
    
    /// Icon name for this device genre
    var iconName: String {
        switch self {
        case .bitaxe:
            return "BitaxeGamma"  // Default Bitaxe icon
        case .nerdQAxe:
            return "NerdQAxePlus"  // Default NerdQAxe icon
        case .avalon:
            return "AvalonMiner"  // Avalon icon
        case .unknown:
            return "UnknownMiner"
        }
    }
}
