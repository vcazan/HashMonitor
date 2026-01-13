//
//  KnownMiners.swift
//  HashRipper
//
//  Created by Matt Sellars
//
import AxeOSClient

enum MinerType {
    // Bitaxe devices (AxeOS)
    case BitaxeUltra // 200
    case BitaxeSupra // 400
    case BitaxeGamma // 600
    case BitaxeGammaTurbo // 800

    // NerdQAxe devices (AxeOS)
    case NerdQAxePlus // deviceModel "NerdQAxe+"
    case NerdQAxePlusPlus // deviceModel "NerdQAxe++"
    case NerdOCTAXE // deviceModel "NerdOCTAXE-γ"
    case NerdQX // deviceModel NerdQX
    
    // Avalon devices (CGMiner API)
    case Avalon10 // Avalon 10xx series (e.g., 1046, 1066)
    case Avalon11 // Avalon 11xx series (e.g., 1126, 1166)
    case Avalon12 // Avalon 12xx series (e.g., 1246, 1266)
    case Avalon13 // Avalon 13xx series
    case Avalon14 // Avalon 14xx series
    case Avalon15 // Avalon 15xx series
    case Avalon16 // Avalon 16xx series (A16)
    case AvalonNano // Avalon Nano series
    case AvalonGeneric // Generic/unknown Avalon miner
    
    case Unknown

    var deviceGenre: MinerDeviceGenre {
        switch self {
        case .BitaxeGamma, .BitaxeGammaTurbo, .BitaxeSupra, .BitaxeUltra:
            return .bitaxe
        case .NerdQAxePlus, .NerdQAxePlusPlus, .NerdOCTAXE, .NerdQX:
            return .nerdQAxe
        case .Avalon10, .Avalon11, .Avalon12, .Avalon13, .Avalon14, .Avalon15, .Avalon16, .AvalonNano, .AvalonGeneric:
            return .avalon
        case .Unknown:
            return .unknown
        }
    }
    
    /// Display name for this miner type
    var displayName: String {
        switch self {
        case .BitaxeUltra: return "Bitaxe Ultra"
        case .BitaxeSupra: return "Bitaxe Supra"
        case .BitaxeGamma: return "Bitaxe Gamma"
        case .BitaxeGammaTurbo: return "Bitaxe Gamma Turbo"
        case .NerdQAxePlus: return "NerdQAxe+"
        case .NerdQAxePlusPlus: return "NerdQAxe++"
        case .NerdOCTAXE: return "NerdOCTAXE-γ"
        case .NerdQX: return "NerdQX"
        case .Avalon10: return "Avalon 10xx"
        case .Avalon11: return "Avalon 11xx"
        case .Avalon12: return "Avalon 12xx"
        case .Avalon13: return "Avalon 13xx"
        case .Avalon14: return "Avalon 14xx"
        case .Avalon15: return "Avalon 15xx"
        case .Avalon16: return "Avalon A16"
        case .AvalonNano: return "Avalon Nano"
        case .AvalonGeneric: return "Avalon Miner"
        case .Unknown: return "Unknown"
        }
    }
    
    /// Icon name for this miner type
    var iconName: String {
        switch self {
        case .BitaxeUltra: return "BitaxeUltra"
        case .BitaxeSupra: return "BitaxeSupra"
        case .BitaxeGamma: return "BitaxeGamma"
        case .BitaxeGammaTurbo: return "BitaxeGammaTurbo"
        case .NerdQAxePlus: return "NerdQAxePlus"
        case .NerdQAxePlusPlus: return "NerdQAxePlusPlus"
        case .NerdOCTAXE: return "NerdOctaxe"
        case .NerdQX: return "NerdQX"
        case .Avalon10, .Avalon11, .Avalon12, .Avalon13, .Avalon14, .Avalon15, .Avalon16, .AvalonNano, .AvalonGeneric:
            return "AvalonQ"
        case .Unknown: return "UnknownMiner"
        }
    }
    
    /// Initialize from Avalon device model string
    static func fromAvalonModel(_ model: String) -> MinerType {
        let lowercased = model.lowercased()
        
        if lowercased.contains("nano") {
            return .AvalonNano
        } else if lowercased.contains("10") || lowercased.contains("1046") || lowercased.contains("1066") {
            return .Avalon10
        } else if lowercased.contains("11") || lowercased.contains("1126") || lowercased.contains("1166") {
            return .Avalon11
        } else if lowercased.contains("12") || lowercased.contains("1246") || lowercased.contains("1266") {
            return .Avalon12
        } else if lowercased.contains("13") {
            return .Avalon13
        } else if lowercased.contains("14") {
            return .Avalon14
        } else if lowercased.contains("15") {
            return .Avalon15
        } else if lowercased.contains("16") || lowercased.contains("a16") {
            return .Avalon16
        } else if lowercased.contains("avalon") {
            return .AvalonGeneric
        }
        
        return .Unknown
    }
}

extension Miner {
    var minerDeviceDisplayName: String {
        // Check if this is an Avalon miner
        if self.isAvalonMiner {
            if let deviceModel = self.deviceModel, !deviceModel.isEmpty {
                return deviceModel
            }
            return "Avalon Miner"
        }
        
        // AxeOS-based miners
        switch ((self.boardVersion, self.deviceModel)) {
        case (.none, .none):
            return "Unknown"

        case let (.none, .some(deviceModel)):
            return deviceModel

        case (let .some(boardVersion), _):
            guard let boardVersionInt = Int(boardVersion) else {
                return "Unknown"
            }
            switch (boardVersionInt) {
            case (200..<300):
                return "Bitaxe Ultra"
            case (400..<500):
                return "Bitaxe Supra"
            case (600..<700):
                return "Bitaxe Gamma"
            case (800..<900):
                return "Bitaxe Gamma Turbo"
            default:
                return "Unknown"
            }

        case(_, _):
            return "Unknown"
        }
    }

    var minerType: MinerType {
        // Check if this is an Avalon miner
        if self.isAvalonMiner {
            if let deviceModel = self.deviceModel {
                return MinerType.fromAvalonModel(deviceModel)
            }
            return .AvalonGeneric
        }
        
        // AxeOS-based miners
        switch ((self.boardVersion, self.deviceModel)) {
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
            switch (boardVersionInt) {
            case (200..<300):
                return .BitaxeUltra
            case (400..<500):
                return .BitaxeSupra
            case (600..<700):
                return .BitaxeGamma
            case (800..<900):
                return .BitaxeGammaTurbo
            default:
                return .Unknown
            }

        case(_, _):
            return .Unknown
        }
    }

    var qAxeMinerIdentifier: String? {
        guard self.minerType.deviceGenre == .nerdQAxe else {
            return nil
        }

        if self.minerType == .NerdQAxePlus {
            return "NerdQAxe+"
        }
        if self.minerType == .NerdQAxePlusPlus {
            return "NerdQAxe++"
        }
        if (self.minerType == .NerdQX) {
            return "NerdQX"
        }

        return nil
    }
}

extension AxeOSDeviceInfo {
    var minerType: MinerType {
        switch ((self.boardVersion, self.deviceModel)) {
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
            switch (boardVersionInt) {
            case (200..<300):
                return .BitaxeUltra
            case (400..<500):
                return .BitaxeSupra
            case (600..<700):
                return .BitaxeGamma
            case (800..<900):
                return .BitaxeGammaTurbo
            default:
                return .Unknown
            }

        case(_, _):
            return .Unknown
        }
    }

    var minerDeviceDisplayName: String {
        switch ((self.boardVersion, self.deviceModel)) {
        case (.none, .none):
            return "Unknown"

        case let (.none, .some(deviceModel)):
            return deviceModel

        case (let .some(boardVersion), _):
            guard let boardVersionInt = Int(boardVersion) else {
                return "Unknown"
            }
            switch (boardVersionInt) {
            case (200..<300):
                return "Bitaxe Ultra"
            case (400..<500):
                return "Bitaxe Supra"
            case (600..<700):
                return "Bitaxe Gamma"
            case (800..<900):
                return "Bitaxe Gamma Turbo"
            default:
                return "Unknown"
            }

        case(_, _):
            return "Unknown"
        }
    }
}
