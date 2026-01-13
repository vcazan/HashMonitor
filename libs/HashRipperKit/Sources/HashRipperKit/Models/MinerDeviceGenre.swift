//
//  MinerDeviceGenre.swift
//  HashRipperKit
//
//  Shared cross-platform model
//

import Foundation

public enum MinerDeviceGenre: String, CaseIterable, Sendable, Codable {
    case bitaxe
    case nerdQAxe
    case avalon
    case unknown
    
    public var name: String {
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
    
    public var firmwareUpdateUrlString: String? {
        switch self {
        case .bitaxe:
            return "https://api.github.com/repos/bitaxeorg/esp-miner/releases"
        case .nerdQAxe:
            return "https://api.github.com/repos/shufps/esp-miner-nerdqaxeplus/releases"
        case .avalon:
            return nil  // Avalon firmware updates not managed via GitHub
        case .unknown:
            return nil
        }
    }
    
    public var firmwareUpdateUrl: URL? {
        guard let string = firmwareUpdateUrlString else {
            return nil
        }
        return URL(string: string)
    }
}

