//
//  MinerType.swift
//  HashRipperKit
//
//  Shared cross-platform model
//

import Foundation
import AxeOSClient

public enum MinerType: String, CaseIterable, Sendable, Codable {
    case BitaxeUltra      // 200
    case BitaxeSupra      // 400
    case BitaxeGamma      // 600
    case BitaxeGammaTurbo // 800
    case NerdQAxePlus     // deviceModel "NerdQAxe+"
    case NerdQAxePlusPlus // deviceModel "NerdQAxe++"
    case NerdOCTAXE       // deviceModel "NerdOCTAXE-γ"
    case NerdQX           // deviceModel NerdQX
    case Unknown

    public var deviceGenre: MinerDeviceGenre {
        switch self {
        case .BitaxeGamma, .BitaxeGammaTurbo, .BitaxeSupra, .BitaxeUltra:
            return .bitaxe
        case .NerdQAxePlus, .NerdQAxePlusPlus, .NerdOCTAXE, .NerdQX:
            return .nerdQAxe
        case .Unknown:
            return .unknown
        }
    }
    
    public var displayName: String {
        switch self {
        case .BitaxeUltra: return "Bitaxe Ultra"
        case .BitaxeSupra: return "Bitaxe Supra"
        case .BitaxeGamma: return "Bitaxe Gamma"
        case .BitaxeGammaTurbo: return "Bitaxe Gamma Turbo"
        case .NerdQAxePlus: return "NerdQAxe+"
        case .NerdQAxePlusPlus: return "NerdQAxe++"
        case .NerdOCTAXE: return "NerdOCTAXE-γ"
        case .NerdQX: return "NerdQX"
        case .Unknown: return "Unknown"
        }
    }
    
    public var imageName: String {
        switch self {
        case .BitaxeUltra: return "BitaxeUltra"
        case .BitaxeSupra: return "BitaxeSupra"
        case .BitaxeGamma: return "BitaxeGamma"
        case .BitaxeGammaTurbo: return "BitaxeGammaTurbo"
        case .NerdQAxePlus: return "NerdQAxePlus"
        case .NerdQAxePlusPlus: return "NerdQAxePlusPlus"
        case .NerdOCTAXE: return "NerdOctaxe"
        case .NerdQX: return "NerdQX"
        case .Unknown: return "UnknownMiner"
        }
    }
}

// MARK: - Helper to determine MinerType from board/device info

public extension MinerType {
    static func from(boardVersion: String?, deviceModel: String?) -> MinerType {
        switch (boardVersion, deviceModel) {
        case (.none, .none):
            return .Unknown
        case (.none, .some("NerdQAxe+")):
            return .NerdQAxePlus
        case (.none, .some("NerdQAxe++")):
            return .NerdQAxePlusPlus
        case (.none, .some("NerdOCTAXE-γ")):
            return .NerdOCTAXE
        case (.none, .some("NerdQX")):
            return .NerdQX
        case (let .some(boardVersion), _):
            guard let boardVersionInt = Int(boardVersion) else {
                return .Unknown
            }
            switch boardVersionInt {
            case 200..<300: return .BitaxeUltra
            case 400..<500: return .BitaxeSupra
            case 600..<700: return .BitaxeGamma
            case 800..<900: return .BitaxeGammaTurbo
            default: return .Unknown
            }
        default:
            return .Unknown
        }
    }
    
    static func displayName(boardVersion: String?, deviceModel: String?) -> String {
        switch (boardVersion, deviceModel) {
        case (.none, .none):
            return "Unknown"
        case (.none, .some(let deviceModel)):
            return deviceModel
        case (.some(let boardVersion), _):
            guard let boardVersionInt = Int(boardVersion) else {
                return "Unknown"
            }
            switch boardVersionInt {
            case 200..<300: return "Bitaxe Ultra"
            case 400..<500: return "Bitaxe Supra"
            case 600..<700: return "Bitaxe Gamma"
            case 800..<900: return "Bitaxe Gamma Turbo"
            default: return "Unknown"
            }
        default:
            return "Unknown"
        }
    }
}

// MARK: - AxeOSDeviceInfo Extension

public extension AxeOSDeviceInfo {
    var minerType: MinerType {
        MinerType.from(boardVersion: self.boardVersion, deviceModel: self.deviceModel)
    }
    
    var minerDeviceDisplayName: String {
        MinerType.displayName(boardVersion: self.boardVersion, deviceModel: self.deviceModel)
    }
}

