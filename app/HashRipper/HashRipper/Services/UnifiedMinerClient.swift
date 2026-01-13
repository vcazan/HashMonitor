//
//  UnifiedMinerClient.swift
//  HashRipper
//
//  Unified abstraction layer for communicating with different miner types
//  (AxeOS-based miners and Avalon/CGMiner miners)
//

import Foundation
import AxeOSClient
import AvalonClient

// MARK: - Unified Device Info

/// Unified device information that works with all miner types
struct UnifiedMinerInfo: Sendable {
    // Identification
    let hostname: String
    let macAddress: String
    let ipAddress: String
    let deviceModel: String
    let firmwareVersion: String
    let protocolType: MinerProtocolType
    
    // Mining Stats
    let hashRate: Double  // In GH/s for Avalon, H/s for AxeOS (normalize in display)
    let sharesAccepted: Int
    let sharesRejected: Int
    let bestDiff: String?
    let bestSessionDiff: String?
    
    // Pool Information
    let stratumURL: String
    let stratumPort: Int
    let stratumUser: String
    let fallbackStratumURL: String?
    let fallbackStratumPort: Int?
    let fallbackStratumUser: String?
    let isUsingFallbackStratum: Bool
    
    // Hardware Status
    let temperature: Double
    let vrTemp: Double?
    let fanSpeed: Int  // RPM
    let fanSpeedPercent: Double?
    let voltage: Double?
    let frequency: Double?
    let power: Double
    let coreVoltage: Int?
    
    // System Info
    let uptimeSeconds: Int
    
    // AxeOS-specific
    let boardVersion: String?
    let axeOSVersion: String?
    let autofanspeed: Int?
    let flipscreen: Int?
    let invertscreen: Int?
    let invertfanpolarity: Int?
    
    // Avalon-specific
    let asicCount: Int?
    let chainCount: Int?
    let hardwareErrors: Int?
    let staleShares: Int?
    
    /// Initialize from AxeOS device info
    init(from axeOS: AxeOSDeviceInfo, ipAddress: String) {
        self.hostname = axeOS.hostname
        self.macAddress = axeOS.macAddr
        self.ipAddress = ipAddress
        self.deviceModel = axeOS.deviceModel ?? axeOS.ASICModel
        self.firmwareVersion = axeOS.version
        self.protocolType = .axeOS
        
        self.hashRate = axeOS.hashRate ?? 0
        self.sharesAccepted = axeOS.sharesAccepted ?? 0
        self.sharesRejected = axeOS.sharesRejected ?? 0
        self.bestDiff = axeOS.bestDiff
        self.bestSessionDiff = axeOS.bestSessionDiff
        
        self.stratumURL = axeOS.stratumURL
        self.stratumPort = axeOS.stratumPort
        self.stratumUser = axeOS.stratumUser
        self.fallbackStratumURL = axeOS.fallbackStratumURL
        self.fallbackStratumPort = axeOS.fallbackStratumPort
        self.fallbackStratumUser = axeOS.fallbackStratumUser
        self.isUsingFallbackStratum = axeOS.isUsingFallbackStratum
        
        self.temperature = axeOS.temp ?? 0
        self.vrTemp = axeOS.vrTemp
        self.fanSpeed = axeOS.fanrpm ?? 0
        self.fanSpeedPercent = axeOS.fanspeed
        self.voltage = axeOS.voltage
        self.frequency = axeOS.frequency
        self.power = axeOS.power ?? 0
        self.coreVoltage = axeOS.coreVoltage
        
        self.uptimeSeconds = axeOS.uptimeSeconds ?? 0
        
        self.boardVersion = axeOS.boardVersion
        self.axeOSVersion = axeOS.axeOSVersion
        self.autofanspeed = axeOS.autofanspeed
        self.flipscreen = axeOS.flipscreen
        self.invertscreen = axeOS.invertscreen
        self.invertfanpolarity = axeOS.invertfanpolarity
        
        self.asicCount = nil
        self.chainCount = nil
        self.hardwareErrors = nil
        self.staleShares = nil
    }
    
    /// Initialize from Avalon device info
    init(from avalon: AvalonDeviceInfo, ipAddress: String) {
        self.hostname = avalon.hostname
        self.macAddress = avalon.macAddr
        self.ipAddress = ipAddress
        self.deviceModel = avalon.deviceModel
        self.firmwareVersion = avalon.firmwareVersion
        self.protocolType = .cgminer
        
        // Avalon returns hash rate in GH/s, convert to H/s for consistency
        self.hashRate = avalon.hashRate * 1_000_000_000
        self.sharesAccepted = avalon.sharesAccepted
        self.sharesRejected = avalon.sharesRejected
        self.bestDiff = avalon.bestDiff
        self.bestSessionDiff = nil
        
        self.stratumURL = avalon.stratumURL
        self.stratumPort = avalon.stratumPort
        self.stratumUser = avalon.stratumUser
        self.fallbackStratumURL = nil
        self.fallbackStratumPort = nil
        self.fallbackStratumUser = nil
        self.isUsingFallbackStratum = false
        
        self.temperature = avalon.temperature
        self.vrTemp = nil
        self.fanSpeed = avalon.fanSpeed
        self.fanSpeedPercent = Double(avalon.fanSpeedPercent)
        self.voltage = avalon.voltage
        self.frequency = avalon.frequency
        self.power = avalon.power
        self.coreVoltage = nil
        
        self.uptimeSeconds = avalon.uptimeSeconds
        
        self.boardVersion = nil
        self.axeOSVersion = nil
        self.autofanspeed = nil
        self.flipscreen = nil
        self.invertscreen = nil
        self.invertfanpolarity = nil
        
        self.asicCount = avalon.asicCount
        self.chainCount = avalon.chainCount
        self.hardwareErrors = avalon.hardwareErrors
        self.staleShares = avalon.staleShares
    }
}

// MARK: - Unified Miner Client

/// Errors that can occur when using the unified miner client
enum UnifiedMinerClientError: Error, Sendable {
    case unknownProtocol
    case connectionFailed(String)
    case timeout
    case invalidResponse(String)
    case operationNotSupported(String)
}

/// A unified client that wraps either an AxeOS or Avalon client
final class UnifiedMinerClient: Identifiable, @unchecked Sendable {
    var id: String { ipAddress }
    
    let ipAddress: String
    let protocolType: MinerProtocolType
    
    private let axeOSClient: AxeOSClient?
    private let avalonClient: AvalonClient?
    
    /// Create a client for an AxeOS miner
    init(axeOSClient: AxeOSClient) {
        self.ipAddress = axeOSClient.deviceIpAddress
        self.protocolType = .axeOS
        self.axeOSClient = axeOSClient
        self.avalonClient = nil
    }
    
    /// Create a client for an Avalon miner
    init(avalonClient: AvalonClient) {
        self.ipAddress = avalonClient.deviceIpAddress
        self.protocolType = .cgminer
        self.axeOSClient = nil
        self.avalonClient = avalonClient
    }
    
    /// Create a client based on protocol type
    init(ipAddress: String, protocolType: MinerProtocolType, urlSession: URLSession? = nil) {
        self.ipAddress = ipAddress
        self.protocolType = protocolType
        
        switch protocolType {
        case .axeOS:
            let session = urlSession ?? URLSession.shared
            self.axeOSClient = AxeOSClient(deviceIpAddress: ipAddress, urlSession: session)
            self.avalonClient = nil
        case .cgminer:
            self.axeOSClient = nil
            self.avalonClient = AvalonClient(deviceIpAddress: ipAddress)
        case .unknown:
            self.axeOSClient = nil
            self.avalonClient = nil
        }
    }
    
    /// Get system information from the miner
    func getSystemInfo() async -> Result<UnifiedMinerInfo, Error> {
        switch protocolType {
        case .axeOS:
            guard let client = axeOSClient else {
                return .failure(UnifiedMinerClientError.unknownProtocol)
            }
            let result = await client.getSystemInfo()
            switch result {
            case .success(let info):
                return .success(UnifiedMinerInfo(from: info, ipAddress: ipAddress))
            case .failure(let error):
                return .failure(error)
            }
            
        case .cgminer:
            guard let client = avalonClient else {
                return .failure(UnifiedMinerClientError.unknownProtocol)
            }
            let result = await client.getDeviceInfo()
            switch result {
            case .success(let info):
                return .success(UnifiedMinerInfo(from: info, ipAddress: ipAddress))
            case .failure(let error):
                return .failure(error)
            }
            
        case .unknown:
            return .failure(UnifiedMinerClientError.unknownProtocol)
        }
    }
    
    /// Restart the miner
    func restart() async -> Result<Bool, Error> {
        switch protocolType {
        case .axeOS:
            guard let client = axeOSClient else {
                return .failure(UnifiedMinerClientError.unknownProtocol)
            }
            let result = await client.restartClient()
            switch result {
            case .success(let success):
                return .success(success)
            case .failure(let error):
                return .failure(error)
            }
            
        case .cgminer:
            guard let client = avalonClient else {
                return .failure(UnifiedMinerClientError.unknownProtocol)
            }
            let result = await client.restart()
            switch result {
            case .success(let success):
                return .success(success)
            case .failure(let error):
                return .failure(error)
            }
            
        case .unknown:
            return .failure(UnifiedMinerClientError.unknownProtocol)
        }
    }
    
    /// Update pool settings (AxeOS only for now)
    func updatePoolSettings(
        stratumURL: String,
        stratumPort: Int,
        stratumUser: String,
        stratumPassword: String = "x",
        fallbackStratumURL: String? = nil,
        fallbackStratumPort: Int? = nil,
        fallbackStratumUser: String? = nil,
        fallbackStratumPassword: String? = nil
    ) async -> Result<Bool, Error> {
        switch protocolType {
        case .axeOS:
            guard let client = axeOSClient else {
                return .failure(UnifiedMinerClientError.unknownProtocol)
            }
            
            let settings = MinerSettings(
                stratumURL: stratumURL,
                fallbackStratumURL: fallbackStratumURL,
                stratumUser: stratumUser,
                stratumPassword: stratumPassword,
                fallbackStratumUser: fallbackStratumUser,
                fallbackStratumPassword: fallbackStratumPassword,
                stratumPort: stratumPort,
                fallbackStratumPort: fallbackStratumPort,
                ssid: nil,
                wifiPass: nil,
                hostname: nil,
                coreVoltage: nil,
                frequency: nil,
                flipscreen: nil,
                overheatMode: nil,
                overclockEnabled: nil,
                invertscreen: nil,
                invertfanpolarity: nil,
                autofanspeed: nil,
                fanspeed: nil
            )
            
            let result = await client.updateSystemSettings(settings: settings)
            switch result {
            case .success(let success):
                return .success(success)
            case .failure(let error):
                return .failure(error)
            }
            
        case .cgminer:
            guard let client = avalonClient else {
                return .failure(UnifiedMinerClientError.unknownProtocol)
            }
            
            // Avalon uses addpool command
            let poolURL = "stratum+tcp://\(stratumURL):\(stratumPort)"
            let result = await client.addPool(url: poolURL, user: stratumUser, password: stratumPassword)
            switch result {
            case .success(let success):
                return .success(success)
            case .failure(let error):
                return .failure(error)
            }
            
        case .unknown:
            return .failure(UnifiedMinerClientError.unknownProtocol)
        }
    }
    
    /// Upload firmware (AxeOS only)
    func uploadFirmware(from fileURL: URL, progressCallback: ((Double) -> Void)? = nil) async -> Result<Bool, Error> {
        switch protocolType {
        case .axeOS:
            guard let client = axeOSClient else {
                return .failure(UnifiedMinerClientError.unknownProtocol)
            }
            let result = await client.uploadFirmware(from: fileURL, progressCallback: progressCallback)
            switch result {
            case .success(let success):
                return .success(success)
            case .failure(let error):
                return .failure(error)
            }
            
        case .cgminer:
            return .failure(UnifiedMinerClientError.operationNotSupported("Avalon firmware updates are not supported through this interface"))
            
        case .unknown:
            return .failure(UnifiedMinerClientError.unknownProtocol)
        }
    }
    
    /// Get the underlying AxeOS client if available
    var axeOS: AxeOSClient? {
        return axeOSClient
    }
    
    /// Get the underlying Avalon client if available
    var avalon: AvalonClient? {
        return avalonClient
    }
}

// MARK: - Discovery Support

/// A discovered miner from network scanning
struct DiscoveredMiner: Sendable {
    let client: UnifiedMinerClient
    let info: UnifiedMinerInfo
    
    init(client: UnifiedMinerClient, info: UnifiedMinerInfo) {
        self.client = client
        self.info = info
    }
}
