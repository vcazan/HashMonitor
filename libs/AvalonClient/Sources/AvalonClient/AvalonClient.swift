//
//  AvalonClient.swift
//  AvalonClient
//
//  Client for communicating with Avalon miners via the CGMiner API (TCP port 4028)
//

@preconcurrency import Foundation
import Network

public enum AvalonClientError: Error, Sendable {
    case connectionFailed(String)
    case connectionTimeout
    case sendFailed(String)
    case receiveFailed(String)
    case invalidResponse(String)
    case decodingError(String)
    case commandFailed(String)
    case notConnected
}

/// Client for communicating with Avalon miners via CGMiner API over TCP port 4028
public final class AvalonClient: Identifiable, @unchecked Sendable {
    public static let defaultPort: UInt16 = 4028
    public static let defaultTimeout: TimeInterval = 10.0
    
    public var id: String { deviceIpAddress }
    
    public let deviceIpAddress: String
    public let port: UInt16
    private let timeout: TimeInterval
    
    public init(
        deviceIpAddress: String,
        port: UInt16 = AvalonClient.defaultPort,
        timeout: TimeInterval = AvalonClient.defaultTimeout
    ) {
        self.deviceIpAddress = deviceIpAddress
        self.port = port
        self.timeout = timeout
    }
    
    // MARK: - Public API Methods
    
    /// Get complete device information by combining multiple API calls
    public func getDeviceInfo() async -> Result<AvalonDeviceInfo, Error> {
        do {
            // Fetch summary, pools, estats, and version concurrently
            async let summaryResult = sendCommand("summary")
            async let poolsResult = sendCommand("pools")
            async let estatsResult = sendCommand("estats")
            async let versionResult = sendCommand("version")
            
            let summaryRaw = try await summaryResult
            let poolsRaw = try await poolsResult
            let estatsRaw = try await estatsResult
            let versionRaw = try await versionResult
            
            // Parse pipe-delimited responses
            let summaryParsed = CGMinerResponseParser.parse(summaryRaw)
            let poolsParsed = CGMinerResponseParser.parse(poolsRaw)
            let versionParsed = CGMinerResponseParser.parse(versionRaw)
            
            // Extract bracket metrics from estats (e.g., GHSspd[96557.33])
            let estatsMetrics = CGMinerResponseParser.extractBracketMetrics(estatsRaw)
            
            // Build device info from responses
            let deviceInfo = buildDeviceInfo(
                summary: summaryParsed,
                pools: poolsParsed,
                estats: estatsMetrics,
                version: versionParsed
            )
            
            return .success(deviceInfo)
            
        } catch let error as AvalonClientError {
            return .failure(error)
        } catch {
            return .failure(AvalonClientError.decodingError(error.localizedDescription))
        }
    }
    
    /// Restart the miner
    public func restart() async -> Result<Bool, AvalonClientError> {
        do {
            let _ = try await sendCommand("restart")
            return .success(true)
        } catch let error as AvalonClientError {
            return .failure(error)
        } catch {
            return .failure(.commandFailed(error.localizedDescription))
        }
    }
    
    /// Add or update a pool
    public func addPool(url: String, user: String, password: String = "x") async -> Result<Bool, AvalonClientError> {
        do {
            let command = "addpool|\(url),\(user),\(password)"
            let _ = try await sendCommand(command)
            return .success(true)
        } catch let error as AvalonClientError {
            return .failure(error)
        } catch {
            return .failure(.commandFailed(error.localizedDescription))
        }
    }
    
    /// Switch to a different pool
    public func switchPool(poolIndex: Int) async -> Result<Bool, AvalonClientError> {
        do {
            let _ = try await sendCommand("switchpool|\(poolIndex)")
            return .success(true)
        } catch let error as AvalonClientError {
            return .failure(error)
        } catch {
            return .failure(.commandFailed(error.localizedDescription))
        }
    }
    
    /// Set fan speed (0-100%)
    /// Note: The actual command format may vary by firmware version
    public func setFanSpeed(percent: Int) async -> Result<Bool, AvalonClientError> {
        let clampedPercent = max(0, min(100, percent))
        do {
            // Try ascset command format used by many CGMiner implementations
            let _ = try await sendCommand("ascset|0,fan,\(clampedPercent)")
            return .success(true)
        } catch let error as AvalonClientError {
            return .failure(error)
        } catch {
            return .failure(.commandFailed(error.localizedDescription))
        }
    }
    
    /// Set performance mode / frequency
    /// Mode can be: "normal", "high", "low" or a frequency value
    public func setPerformanceMode(mode: String) async -> Result<Bool, AvalonClientError> {
        do {
            // Try ascset command for performance/frequency
            let _ = try await sendCommand("ascset|0,freq,\(mode)")
            return .success(true)
        } catch let error as AvalonClientError {
            return .failure(error)
        } catch {
            return .failure(.commandFailed(error.localizedDescription))
        }
    }
    
    /// Set target frequency in MHz
    public func setFrequency(mhz: Int) async -> Result<Bool, AvalonClientError> {
        do {
            let _ = try await sendCommand("ascset|0,freq,\(mhz)")
            return .success(true)
        } catch let error as AvalonClientError {
            return .failure(error)
        } catch {
            return .failure(.commandFailed(error.localizedDescription))
        }
    }
    
    // MARK: - Private Methods
    
    /// Send a command to the miner and receive the response
    /// Commands are sent as raw ASCII text (NOT JSON wrapped)
    private func sendCommand(_ command: String) async throws -> String {
        let ipAddress = self.deviceIpAddress
        let portNumber = self.port
        let timeoutInterval = self.timeout
        
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            let host = NWEndpoint.Host(ipAddress)
            let port = NWEndpoint.Port(rawValue: portNumber)!
            
            let connection = NWConnection(host: host, port: port, using: .tcp)
            
            // Use actor for thread-safe state management
            let state = ConnectionState()
            
            @Sendable func resumeOnce(_ result: Result<String, Error>) {
                Task {
                    let didResume = await state.tryResume()
                    if didResume {
                        connection.cancel()
                        continuation.resume(with: result)
                    }
                }
            }
            
            // Set up timeout using Task
            Task {
                try? await Task.sleep(nanoseconds: UInt64(timeoutInterval * 1_000_000_000))
                resumeOnce(.failure(AvalonClientError.connectionTimeout))
            }
            
            connection.stateUpdateHandler = { connectionState in
                switch connectionState {
                case .ready:
                    // Connection established, send command as raw ASCII (like the Python script does)
                    let commandData = Data(command.utf8)
                    connection.send(content: commandData, completion: .contentProcessed { error in
                        if let error = error {
                            resumeOnce(.failure(AvalonClientError.sendFailed(error.localizedDescription)))
                            return
                        }
                        
                        // Receive response
                        Self.receiveResponse(connection: connection) { result in
                            resumeOnce(result)
                        }
                    })
                    
                case .failed(let error):
                    resumeOnce(.failure(AvalonClientError.connectionFailed(error.localizedDescription)))
                    
                case .cancelled:
                    // Already handled
                    break
                    
                default:
                    break
                }
            }
            
            connection.start(queue: .global())
        }
    }
    
    /// Receive the complete response from the connection
    private static func receiveResponse(connection: NWConnection, completion: @escaping @Sendable (Result<String, Error>) -> Void) {
        let dataCollector = DataCollector()
        
        @Sendable func receive() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
                if let error = error {
                    completion(.failure(AvalonClientError.receiveFailed(error.localizedDescription)))
                    return
                }
                
                Task {
                    if let data = data {
                        await dataCollector.append(data)
                    }
                    
                    if isComplete {
                        let receivedData = await dataCollector.getData()
                        guard let responseString = String(data: receivedData, encoding: .utf8) else {
                            completion(.failure(AvalonClientError.invalidResponse("Could not decode response as UTF-8")))
                            return
                        }
                        
                        // Clean up null bytes and whitespace
                        let cleanedResponse = responseString.trimmingCharacters(in: CharacterSet(charactersIn: "\0\r\n "))
                        completion(.success(cleanedResponse))
                    } else {
                        receive()
                    }
                }
            }
        }
        
        receive()
    }
    
    /// Build AvalonDeviceInfo from parsed API responses
    private func buildDeviceInfo(
        summary: [String: [String: String]],
        pools: [String: [String: String]],
        estats: [String: String],
        version: [String: [String: String]]
    ) -> AvalonDeviceInfo {
        // Flatten parsed sections
        let summaryFlat = summary.values.reduce(into: [String: String]()) { result, dict in
            dict.forEach { result[$0.key] = $0.value }
        }
        let poolsFlat = pools.values.reduce(into: [String: String]()) { result, dict in
            dict.forEach { result[$0.key] = $0.value }
        }
        let versionFlat = version.values.reduce(into: [String: String]()) { result, dict in
            dict.forEach { result[$0.key] = $0.value }
        }
        
        // Helper to safely parse numbers
        func safeDouble(_ value: String?) -> Double? {
            guard let v = value else { return nil }
            return Double(v)
        }
        func safeInt(_ value: String?) -> Int? {
            guard let v = value else { return nil }
            return Int(Double(v) ?? 0)
        }
        
        // Hash rate from estats (in GH/s) - convert to TH/s for display, but keep as GH/s for storage
        // GHSspd, GHSmm, or GHSavg from estats
        var hashRateGHs: Double = 0
        if let ghs = safeDouble(estats["GHSspd"] ?? estats["GHSmm"] ?? estats["GHSavg"]) {
            hashRateGHs = ghs  // Already in GH/s
        }
        
        // Fallback to summary MHS values (convert MH/s to GH/s)
        if hashRateGHs == 0 {
            if let mhs = safeDouble(summaryFlat["MHS av"]) {
                hashRateGHs = mhs / 1000.0  // MH/s to GH/s
            } else if let mhs5s = safeDouble(summaryFlat["MHS 5s"]) {
                hashRateGHs = mhs5s / 1000.0
            }
        }
        
        // Power from estats PS field (last value is wattage)
        var powerWatts: Double = 0
        if let psRaw = estats["PS"] {
            let parts = psRaw.split(separator: " ")
            if let lastPart = parts.last, let watts = Double(lastPart) {
                powerWatts = watts
            }
        }
        
        // Temperatures from estats
        let tempInternal = safeDouble(estats["ITemp"]) ?? 0  // Intake/Internal temp
        let tempMax = safeDouble(estats["TMax"]) ?? 0        // Max chip temp
        let tempMin = safeDouble(estats["TMin"]) ?? 0        // Min chip temp
        let tempAvg = safeDouble(estats["TAvg"]) ?? 0        // Average chip temp
        let temp1 = safeDouble(estats["Temp1"])
        let temp2 = safeDouble(estats["Temp2"])
        let temp3 = safeDouble(estats["Temp3"])
        let temps = [temp1, temp2, temp3].compactMap { $0 }
        
        // Primary temperature: Use TAvg if available, otherwise average of chip temps, or ITemp
        let temperature = tempAvg > 0 ? tempAvg : (temps.isEmpty ? tempInternal : temps.reduce(0, +) / Double(temps.count))
        
        // Fan speeds from estats
        let fan1 = safeInt(estats["Fan1"]) ?? 0
        let fan2 = safeInt(estats["Fan2"])
        let fan3 = safeInt(estats["Fan3"])
        let fans = [fan1, fan2, fan3].compactMap { $0 }
        let avgFanSpeed = fans.isEmpty ? 0 : fans.reduce(0, +) / fans.count
        
        // Fan percentage from FanR (e.g., "89%")
        var fanPercent = 0
        if let fanR = estats["FanR"] {
            let cleaned = fanR.replacingOccurrences(of: "%", with: "")
            fanPercent = Int(Double(cleaned) ?? 0)
        }
        
        // Pool info
        let poolURL = poolsFlat["URL"] ?? ""
        var stratumHost = ""
        var stratumPort = 3333
        if !poolURL.isEmpty {
            let cleanURL = poolURL
                .replacingOccurrences(of: "stratum+tcp://", with: "")
                .replacingOccurrences(of: "stratum://", with: "")
            let parts = cleanURL.split(separator: ":")
            stratumHost = String(parts.first ?? "")
            if parts.count > 1, let port = Int(parts[1]) {
                stratumPort = port
            }
        }
        let stratumUser = poolsFlat["User"] ?? ""
        let poolStatus = poolsFlat["Status"] ?? "Unknown"
        
        // Uptime from summary or estats
        let elapsed = safeInt(summaryFlat["Elapsed"]) ?? safeInt(estats["Elapsed"]) ?? 0
        
        // Shares from summary
        let accepted = safeInt(summaryFlat["Accepted"]) ?? 0
        let rejected = safeInt(summaryFlat["Rejected"]) ?? 0
        let hwErrors = safeInt(summaryFlat["Hardware Errors"]) ?? 0
        let stale = safeInt(summaryFlat["Stale"]) ?? 0
        
        // Best share
        let bestShareVal = safeInt(summaryFlat["Best Share"]) ?? 0
        let bestDiff = formatDifficulty(bestShareVal)
        
        // Device model from estats or version
        let deviceModel = estats["Type"] ?? versionFlat["Miner"] ?? "Avalon"
        
        // Firmware version
        let firmwareVersion = versionFlat["CGMiner"] ?? estats["SWv1"] ?? "Unknown"
        
        // Frequency and voltage from estats
        let frequency = safeDouble(estats["Freq"]) ?? safeDouble(estats["Frequency"]) ?? 0
        let voltage = safeDouble(estats["Vol"]) ?? safeDouble(estats["Voltage"]) ?? 0
        
        return AvalonDeviceInfo(
            hostname: "avalon-\(deviceIpAddress.split(separator: ".").last ?? "")",
            macAddr: "",  // CGMiner API doesn't provide MAC
            deviceModel: deviceModel,
            firmwareVersion: firmwareVersion,
            hashRate: hashRateGHs,  // In GH/s
            hashRate5s: safeDouble(summaryFlat["MHS 5s"]).map { $0 / 1000.0 } ?? hashRateGHs,
            hashRate1m: safeDouble(summaryFlat["MHS 1m"]).map { $0 / 1000.0 } ?? hashRateGHs,
            hashRate5m: hashRateGHs,
            hashRate15m: hashRateGHs,
            sharesAccepted: accepted,
            sharesRejected: rejected,
            staleShares: stale,
            hardwareErrors: hwErrors,
            stratumURL: stratumHost,
            stratumPort: stratumPort,
            stratumUser: stratumUser,
            poolStatus: poolStatus,
            temperature: temperature,
            temperatures: temps,
            intakeTemp: tempInternal,
            chipTempMax: tempMax,
            chipTempMin: tempMin,
            fanSpeed: avgFanSpeed,
            fanSpeedPercent: fanPercent,
            voltage: voltage,
            frequency: frequency,
            power: powerWatts,
            uptimeSeconds: elapsed,
            elapsed: elapsed,
            asicCount: safeInt(estats["ASIC"]) ?? 0,
            chainCount: safeInt(estats["MM Count"]) ?? 1,
            bestDiff: bestDiff,
            bestShare: bestShareVal
        )
    }
    
    /// Format difficulty number to human-readable string
    private func formatDifficulty(_ value: Int) -> String {
        let doubleValue = Double(value)
        
        if doubleValue >= 1e12 {
            return String(format: "%.2fT", doubleValue / 1e12)
        } else if doubleValue >= 1e9 {
            return String(format: "%.2fG", doubleValue / 1e9)
        } else if doubleValue >= 1e6 {
            return String(format: "%.2fM", doubleValue / 1e6)
        } else if doubleValue >= 1e3 {
            return String(format: "%.2fK", doubleValue / 1e3)
        } else {
            return String(value)
        }
    }
}

// MARK: - CGMiner Response Parser

/// Parser for CGMiner pipe-delimited response format
public enum CGMinerResponseParser {
    
    /// Parse pipe-delimited response like: STATUS=S,...|SUMMARY,Elapsed=...|
    public static func parse(_ raw: String) -> [String: [String: String]] {
        var result: [String: [String: String]] = [:]
        guard !raw.isEmpty else { return result }
        
        let segments = raw.split(separator: "|").map { String($0).trimmingCharacters(in: .whitespaces) }
        
        for segment in segments where !segment.isEmpty {
            let tokens = segment.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
            guard !tokens.isEmpty else { continue }
            
            let firstToken = tokens[0]
            var sectionName: String
            var data: [String: String] = [:]
            var restTokens: [String]
            
            // Check if first token is like "STATUS=S" or just "SUMMARY"
            if firstToken.contains("=") {
                let parts = firstToken.split(separator: "=", maxSplits: 1)
                sectionName = String(parts[0])
                if parts.count > 1 {
                    data[sectionName] = String(parts[1])
                }
                restTokens = Array(tokens.dropFirst())
            } else {
                sectionName = firstToken
                restTokens = Array(tokens.dropFirst())
            }
            
            // Parse remaining key=value pairs
            for token in restTokens {
                if token.contains("=") {
                    let parts = token.split(separator: "=", maxSplits: 1)
                    let key = String(parts[0]).trimmingCharacters(in: .whitespaces)
                    let value = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespaces) : ""
                    data[key] = value
                }
            }
            
            // Merge into result
            if result[sectionName] != nil {
                for (k, v) in data {
                    result[sectionName]![k] = v
                }
            } else {
                result[sectionName] = data
            }
        }
        
        return result
    }
    
    /// Extract KEY[VALUE] pairs from estats response
    /// e.g., "GHSspd[96557.33] ITemp[31] Fan1[2587]"
    public static func extractBracketMetrics(_ text: String) -> [String: String] {
        var metrics: [String: String] = [:]
        guard !text.isEmpty else { return metrics }
        
        // Pattern: word followed by [content]
        let pattern = #"(\w+)\[([^\]]*)\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return metrics }
        
        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: range)
        
        for match in matches {
            if let keyRange = Range(match.range(at: 1), in: text),
               let valueRange = Range(match.range(at: 2), in: text) {
                let key = String(text[keyRange])
                let value = String(text[valueRange]).trimmingCharacters(in: .whitespaces)
                metrics[key] = value
            }
        }
        
        return metrics
    }
}

// MARK: - Thread-Safe Helpers

/// Actor for managing connection state in a thread-safe manner
private actor ConnectionState {
    private var hasResumed = false
    
    func tryResume() -> Bool {
        if hasResumed {
            return false
        }
        hasResumed = true
        return true
    }
}

/// Actor for collecting data in a thread-safe manner
private actor DataCollector {
    private var data = Data()
    
    func append(_ newData: Data) {
        data.append(newData)
    }
    
    func getData() -> Data {
        return data
    }
}

// MARK: - Discovery Support

/// Discovered Avalon device from network scan
public struct DiscoveredAvalonDevice: Sendable {
    public let client: AvalonClient
    public let info: AvalonDeviceInfo
    
    public init(client: AvalonClient, info: AvalonDeviceInfo) {
        self.client = client
        self.info = info
    }
}

/// Scanner for discovering Avalon miners on the network
public final class AvalonDevicesScanner: Sendable {
    public static let shared = AvalonDevicesScanner()
    
    private init() {}
    
    /// Probe a single IP address to check if it's an Avalon miner
    public func probeDevice(ipAddress: String, timeout: TimeInterval = 3.0) async -> DiscoveredAvalonDevice? {
        let client = AvalonClient(deviceIpAddress: ipAddress, timeout: timeout)
        let result = await client.getDeviceInfo()
        
        switch result {
        case .success(let info):
            return DiscoveredAvalonDevice(client: client, info: info)
        case .failure:
            return nil
        }
    }
    
    /// Scan a range of IP addresses for Avalon miners
    public func scanForDevices(
        ipAddresses: [String],
        onDeviceFound: @Sendable @escaping (DiscoveredAvalonDevice) -> Void
    ) async {
        await withTaskGroup(of: Void.self) { group in
            for ipAddress in ipAddresses {
                group.addTask { @Sendable in
                    if let device = await self.probeDevice(ipAddress: ipAddress) {
                        onDeviceFound(device)
                    }
                }
            }
        }
    }
}
