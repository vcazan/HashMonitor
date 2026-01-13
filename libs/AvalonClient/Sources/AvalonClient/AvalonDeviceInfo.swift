//
//  AvalonDeviceInfo.swift
//  AvalonClient
//
//  Represents device information from Avalon miners using the CGMiner API
//

import Foundation

/// Device information parsed from Avalon miner CGMiner API responses
public struct AvalonDeviceInfo: Codable, Sendable {
    // MARK: - Identification
    public let hostname: String
    public let macAddr: String
    public let deviceModel: String
    public let firmwareVersion: String
    
    // MARK: - Mining Stats
    public let hashRate: Double  // In GH/s
    public let hashRate5s: Double  // 5-second average
    public let hashRate1m: Double  // 1-minute average
    public let hashRate5m: Double  // 5-minute average
    public let hashRate15m: Double  // 15-minute average
    
    // MARK: - Share Stats
    public let sharesAccepted: Int
    public let sharesRejected: Int
    public let staleShares: Int
    public let hardwareErrors: Int
    
    // MARK: - Pool Information
    public let stratumURL: String
    public let stratumPort: Int
    public let stratumUser: String
    public let poolStatus: String
    
    // MARK: - Hardware Status
    public let temperature: Double      // Average chip temperature (TAvg)
    public let temperatures: [Double]   // Per-chip temperatures (Temp1, Temp2, Temp3)
    public let intakeTemp: Double       // Intake/Internal temperature (ITemp)
    public let chipTempMax: Double      // Maximum chip temperature (TMax)
    public let chipTempMin: Double      // Minimum chip temperature (TMin)
    public let fanSpeed: Int            // RPM
    public let fanSpeedPercent: Int     // 0-100%
    public let voltage: Double
    public let frequency: Double
    public let power: Double            // Watts
    
    // MARK: - System Info
    public let uptimeSeconds: Int
    public let elapsed: Int  // Mining elapsed time
    public let asicCount: Int
    public let chainCount: Int
    
    // MARK: - Best Difficulty
    public let bestDiff: String?
    public let bestShare: Int
    
    public init(
        hostname: String,
        macAddr: String,
        deviceModel: String,
        firmwareVersion: String,
        hashRate: Double,
        hashRate5s: Double,
        hashRate1m: Double,
        hashRate5m: Double,
        hashRate15m: Double,
        sharesAccepted: Int,
        sharesRejected: Int,
        staleShares: Int,
        hardwareErrors: Int,
        stratumURL: String,
        stratumPort: Int,
        stratumUser: String,
        poolStatus: String,
        temperature: Double,
        temperatures: [Double],
        intakeTemp: Double,
        chipTempMax: Double,
        chipTempMin: Double,
        fanSpeed: Int,
        fanSpeedPercent: Int,
        voltage: Double,
        frequency: Double,
        power: Double,
        uptimeSeconds: Int,
        elapsed: Int,
        asicCount: Int,
        chainCount: Int,
        bestDiff: String?,
        bestShare: Int
    ) {
        self.hostname = hostname
        self.macAddr = macAddr
        self.deviceModel = deviceModel
        self.firmwareVersion = firmwareVersion
        self.hashRate = hashRate
        self.hashRate5s = hashRate5s
        self.hashRate1m = hashRate1m
        self.hashRate5m = hashRate5m
        self.hashRate15m = hashRate15m
        self.sharesAccepted = sharesAccepted
        self.sharesRejected = sharesRejected
        self.staleShares = staleShares
        self.hardwareErrors = hardwareErrors
        self.stratumURL = stratumURL
        self.stratumPort = stratumPort
        self.stratumUser = stratumUser
        self.poolStatus = poolStatus
        self.temperature = temperature
        self.temperatures = temperatures
        self.intakeTemp = intakeTemp
        self.chipTempMax = chipTempMax
        self.chipTempMin = chipTempMin
        self.fanSpeed = fanSpeed
        self.fanSpeedPercent = fanSpeedPercent
        self.voltage = voltage
        self.frequency = frequency
        self.power = power
        self.uptimeSeconds = uptimeSeconds
        self.elapsed = elapsed
        self.asicCount = asicCount
        self.chainCount = chainCount
        self.bestDiff = bestDiff
        self.bestShare = bestShare
    }
}

// MARK: - CGMiner API Response Models

/// Root response wrapper for CGMiner API
public struct CGMinerResponse: Codable, Sendable {
    public let STATUS: [CGMinerStatus]
    
    public init(STATUS: [CGMinerStatus]) {
        self.STATUS = STATUS
    }
}

/// Status object in CGMiner API responses
public struct CGMinerStatus: Codable, Sendable {
    public let STATUS: String  // "S" for success, "E" for error, "W" for warning
    public let When: Int
    public let Code: Int
    public let Msg: String
    public let Description: String
    
    public var isSuccess: Bool {
        STATUS == "S"
    }
    
    public init(STATUS: String, When: Int, Code: Int, Msg: String, Description: String) {
        self.STATUS = STATUS
        self.When = When
        self.Code = Code
        self.Msg = Msg
        self.Description = Description
    }
}

/// Summary response from CGMiner API
public struct CGMinerSummaryResponse: Codable, Sendable {
    public let STATUS: [CGMinerStatus]
    public let SUMMARY: [CGMinerSummary]
    
    public init(STATUS: [CGMinerStatus], SUMMARY: [CGMinerSummary]) {
        self.STATUS = STATUS
        self.SUMMARY = SUMMARY
    }
}

/// Summary data from CGMiner API
public struct CGMinerSummary: Codable, Sendable {
    public let Elapsed: Int
    public let GHS5s: Double?  // Hash rate in GH/s (5 second average)
    public let GHSav: Double?  // Average hash rate
    public let MHS5s: Double?  // Hash rate in MH/s (alternative field name)
    public let MHSav: Double?  // Average hash rate in MH/s
    public let Accepted: Int
    public let Rejected: Int
    public let HardwareErrors: Int?
    public let Stale: Int?
    public let BestShare: Int?
    public let LastGetwork: Int?
    
    // Computed hash rate (handles different field names)
    public var hashRateGHs: Double {
        if let ghs = GHS5s {
            return ghs
        } else if let mhs = MHS5s {
            return mhs / 1000.0
        }
        return 0
    }
    
    public init(
        Elapsed: Int,
        GHS5s: Double? = nil,
        GHSav: Double? = nil,
        MHS5s: Double? = nil,
        MHSav: Double? = nil,
        Accepted: Int,
        Rejected: Int,
        HardwareErrors: Int? = nil,
        Stale: Int? = nil,
        BestShare: Int? = nil,
        LastGetwork: Int? = nil
    ) {
        self.Elapsed = Elapsed
        self.GHS5s = GHS5s
        self.GHSav = GHSav
        self.MHS5s = MHS5s
        self.MHSav = MHSav
        self.Accepted = Accepted
        self.Rejected = Rejected
        self.HardwareErrors = HardwareErrors
        self.Stale = Stale
        self.BestShare = BestShare
        self.LastGetwork = LastGetwork
    }
}

/// Pools response from CGMiner API
public struct CGMinerPoolsResponse: Codable, Sendable {
    public let STATUS: [CGMinerStatus]
    public let POOLS: [CGMinerPool]
    
    public init(STATUS: [CGMinerStatus], POOLS: [CGMinerPool]) {
        self.STATUS = STATUS
        self.POOLS = POOLS
    }
}

/// Pool data from CGMiner API
public struct CGMinerPool: Codable, Sendable {
    public let POOL: Int
    public let URL: String
    public let User: String
    public let Status: String
    public let Priority: Int
    public let Accepted: Int
    public let Rejected: Int
    public let Stale: Int
    public let LastShareTime: Int?
    public let Stratum: Bool?
    public let StratumActive: Bool?
    
    public init(
        POOL: Int,
        URL: String,
        User: String,
        Status: String,
        Priority: Int,
        Accepted: Int,
        Rejected: Int,
        Stale: Int,
        LastShareTime: Int? = nil,
        Stratum: Bool? = nil,
        StratumActive: Bool? = nil
    ) {
        self.POOL = POOL
        self.URL = URL
        self.User = User
        self.Status = Status
        self.Priority = Priority
        self.Accepted = Accepted
        self.Rejected = Rejected
        self.Stale = Stale
        self.LastShareTime = LastShareTime
        self.Stratum = Stratum
        self.StratumActive = StratumActive
    }
}

/// Stats response from CGMiner API (Avalon-specific)
public struct CGMinerStatsResponse: Codable, Sendable {
    public let STATUS: [CGMinerStatus]
    public let STATS: [CGMinerStats]
    
    public init(STATUS: [CGMinerStatus], STATS: [CGMinerStats]) {
        self.STATUS = STATUS
        self.STATS = STATS
    }
}

/// Stats data from CGMiner API (contains Avalon-specific info)
public struct CGMinerStats: Codable, Sendable {
    public let STATS: Int?
    public let ID: String?
    public let Elapsed: Int?
    public let deviceType: String?
    
    // Avalon-specific fields (dynamic based on firmware)
    public let MM_Count: Int?
    public let Fan1: Int?
    public let Fan2: Int?
    public let Fan3: Int?
    public let FanR: Int?
    public let Temp1: Double?
    public let Temp2: Double?
    public let Temp3: Double?
    public let TempMax: Double?
    public let Frequency: Double?
    public let Voltage: Double?
    public let Power: Double?
    public let GHSmm: Double?
    public let GHSavg: Double?
    public let ASIC: Int?
    public let HWv1: String?  // Hardware version
    public let SWv1: String?  // Software version
    
    // Flexible decoding for additional fields
    public let additionalData: [String: AnyCodableValue]?
    
    enum CodingKeys: String, CodingKey {
        case STATS, ID, Elapsed
        case deviceType = "Type"
        case MM_Count = "MM Count"
        case Fan1, Fan2, Fan3, FanR
        case Temp1, Temp2, Temp3, TempMax
        case Frequency, Voltage, Power
        case GHSmm, GHSavg
        case ASIC
        case HWv1, SWv1
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        STATS = try container.decodeIfPresent(Int.self, forKey: .STATS)
        ID = try container.decodeIfPresent(String.self, forKey: .ID)
        Elapsed = try container.decodeIfPresent(Int.self, forKey: .Elapsed)
        deviceType = try container.decodeIfPresent(String.self, forKey: .deviceType)
        MM_Count = try container.decodeIfPresent(Int.self, forKey: .MM_Count)
        Fan1 = try container.decodeIfPresent(Int.self, forKey: .Fan1)
        Fan2 = try container.decodeIfPresent(Int.self, forKey: .Fan2)
        Fan3 = try container.decodeIfPresent(Int.self, forKey: .Fan3)
        FanR = try container.decodeIfPresent(Int.self, forKey: .FanR)
        Temp1 = try container.decodeIfPresent(Double.self, forKey: .Temp1)
        Temp2 = try container.decodeIfPresent(Double.self, forKey: .Temp2)
        Temp3 = try container.decodeIfPresent(Double.self, forKey: .Temp3)
        TempMax = try container.decodeIfPresent(Double.self, forKey: .TempMax)
        Frequency = try container.decodeIfPresent(Double.self, forKey: .Frequency)
        Voltage = try container.decodeIfPresent(Double.self, forKey: .Voltage)
        Power = try container.decodeIfPresent(Double.self, forKey: .Power)
        GHSmm = try container.decodeIfPresent(Double.self, forKey: .GHSmm)
        GHSavg = try container.decodeIfPresent(Double.self, forKey: .GHSavg)
        ASIC = try container.decodeIfPresent(Int.self, forKey: .ASIC)
        HWv1 = try container.decodeIfPresent(String.self, forKey: .HWv1)
        SWv1 = try container.decodeIfPresent(String.self, forKey: .SWv1)
        
        // Capture any additional unknown keys
        additionalData = nil  // TODO: Implement dynamic key capture if needed
    }
    
    public init(
        STATS: Int? = nil,
        ID: String? = nil,
        Elapsed: Int? = nil,
        deviceType: String? = nil,
        MM_Count: Int? = nil,
        Fan1: Int? = nil,
        Fan2: Int? = nil,
        Fan3: Int? = nil,
        FanR: Int? = nil,
        Temp1: Double? = nil,
        Temp2: Double? = nil,
        Temp3: Double? = nil,
        TempMax: Double? = nil,
        Frequency: Double? = nil,
        Voltage: Double? = nil,
        Power: Double? = nil,
        GHSmm: Double? = nil,
        GHSavg: Double? = nil,
        ASIC: Int? = nil,
        HWv1: String? = nil,
        SWv1: String? = nil,
        additionalData: [String: AnyCodableValue]? = nil
    ) {
        self.STATS = STATS
        self.ID = ID
        self.Elapsed = Elapsed
        self.deviceType = deviceType
        self.MM_Count = MM_Count
        self.Fan1 = Fan1
        self.Fan2 = Fan2
        self.Fan3 = Fan3
        self.FanR = FanR
        self.Temp1 = Temp1
        self.Temp2 = Temp2
        self.Temp3 = Temp3
        self.TempMax = TempMax
        self.Frequency = Frequency
        self.Voltage = Voltage
        self.Power = Power
        self.GHSmm = GHSmm
        self.GHSavg = GHSavg
        self.ASIC = ASIC
        self.HWv1 = HWv1
        self.SWv1 = SWv1
        self.additionalData = additionalData
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(STATS, forKey: .STATS)
        try container.encodeIfPresent(ID, forKey: .ID)
        try container.encodeIfPresent(Elapsed, forKey: .Elapsed)
        try container.encodeIfPresent(deviceType, forKey: .deviceType)
        try container.encodeIfPresent(MM_Count, forKey: .MM_Count)
        try container.encodeIfPresent(Fan1, forKey: .Fan1)
        try container.encodeIfPresent(Fan2, forKey: .Fan2)
        try container.encodeIfPresent(Fan3, forKey: .Fan3)
        try container.encodeIfPresent(FanR, forKey: .FanR)
        try container.encodeIfPresent(Temp1, forKey: .Temp1)
        try container.encodeIfPresent(Temp2, forKey: .Temp2)
        try container.encodeIfPresent(Temp3, forKey: .Temp3)
        try container.encodeIfPresent(TempMax, forKey: .TempMax)
        try container.encodeIfPresent(Frequency, forKey: .Frequency)
        try container.encodeIfPresent(Voltage, forKey: .Voltage)
        try container.encodeIfPresent(Power, forKey: .Power)
        try container.encodeIfPresent(GHSmm, forKey: .GHSmm)
        try container.encodeIfPresent(GHSavg, forKey: .GHSavg)
        try container.encodeIfPresent(ASIC, forKey: .ASIC)
        try container.encodeIfPresent(HWv1, forKey: .HWv1)
        try container.encodeIfPresent(SWv1, forKey: .SWv1)
    }
    
    /// Get average temperature from available temp readings
    public var averageTemperature: Double {
        let temps = [Temp1, Temp2, Temp3].compactMap { $0 }
        guard !temps.isEmpty else { return 0 }
        return temps.reduce(0, +) / Double(temps.count)
    }
    
    /// Get average fan speed from available fan readings
    public var averageFanSpeed: Int {
        let fans = [Fan1, Fan2, Fan3].compactMap { $0 }
        guard !fans.isEmpty else { return 0 }
        return fans.reduce(0, +) / fans.count
    }
}

/// Helper for dynamic JSON values
public enum AnyCodableValue: Codable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else {
            throw DecodingError.typeMismatch(
                AnyCodableValue.self,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unsupported type")
            )
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

/// Version response from CGMiner API
public struct CGMinerVersionResponse: Codable, Sendable {
    public let STATUS: [CGMinerStatus]
    public let VERSION: [CGMinerVersion]
    
    public init(STATUS: [CGMinerStatus], VERSION: [CGMinerVersion]) {
        self.STATUS = STATUS
        self.VERSION = VERSION
    }
}

/// Version data from CGMiner API
public struct CGMinerVersion: Codable, Sendable {
    public let CGMiner: String?
    public let API: String?
    public let Miner: String?
    public let CompileTime: String?
    public let minerType: String?
    
    enum CodingKeys: String, CodingKey {
        case CGMiner, API, Miner, CompileTime
        case minerType = "Type"
    }
    
    public init(
        CGMiner: String? = nil,
        API: String? = nil,
        Miner: String? = nil,
        CompileTime: String? = nil,
        minerType: String? = nil
    ) {
        self.CGMiner = CGMiner
        self.API = API
        self.Miner = Miner
        self.CompileTime = CompileTime
        self.minerType = minerType
    }
}

/// Config response from CGMiner API
public struct CGMinerConfigResponse: Codable, Sendable {
    public let STATUS: [CGMinerStatus]
    public let CONFIG: [CGMinerConfig]
    
    public init(STATUS: [CGMinerStatus], CONFIG: [CGMinerConfig]) {
        self.STATUS = STATUS
        self.CONFIG = CONFIG
    }
}

/// Config data from CGMiner API
public struct CGMinerConfig: Codable, Sendable {
    public let ASC_Count: Int?
    public let PGA_Count: Int?
    public let Pool_Count: Int?
    public let Strategy: String?
    public let Failover: Bool?
    public let Hotplug: Int?
    
    enum CodingKeys: String, CodingKey {
        case ASC_Count = "ASC Count"
        case PGA_Count = "PGA Count"
        case Pool_Count = "Pool Count"
        case Strategy, Failover, Hotplug
    }
    
    public init(
        ASC_Count: Int? = nil,
        PGA_Count: Int? = nil,
        Pool_Count: Int? = nil,
        Strategy: String? = nil,
        Failover: Bool? = nil,
        Hotplug: Int? = nil
    ) {
        self.ASC_Count = ASC_Count
        self.PGA_Count = PGA_Count
        self.Pool_Count = Pool_Count
        self.Strategy = Strategy
        self.Failover = Failover
        self.Hotplug = Hotplug
    }
}
