//
//  AvalonClientTests.swift
//  AvalonClientTests
//

import XCTest
@testable import AvalonClient

final class AvalonClientTests: XCTestCase {
    
    // MARK: - Pipe-Delimited Response Parsing Tests
    
    func testParseSummaryResponse() {
        let raw = "STATUS=S,When=1705104000,Code=11,Msg=Summary,Description=cgminer 4.11.1|SUMMARY,Elapsed=86400,MHS av=105230000.00,MHS 5s=105000000.00,MHS 1m=105100000.00,Accepted=12345,Rejected=12,Hardware Errors=5,Best Share=987654321|"
        
        let parsed = CGMinerResponseParser.parse(raw)
        
        // Check STATUS section
        XCTAssertNotNil(parsed["STATUS"])
        XCTAssertEqual(parsed["STATUS"]?["STATUS"], "S")
        XCTAssertEqual(parsed["STATUS"]?["Code"], "11")
        
        // Check SUMMARY section
        XCTAssertNotNil(parsed["SUMMARY"])
        XCTAssertEqual(parsed["SUMMARY"]?["Elapsed"], "86400")
        XCTAssertEqual(parsed["SUMMARY"]?["MHS av"], "105230000.00")
        XCTAssertEqual(parsed["SUMMARY"]?["Accepted"], "12345")
        XCTAssertEqual(parsed["SUMMARY"]?["Rejected"], "12")
        XCTAssertEqual(parsed["SUMMARY"]?["Hardware Errors"], "5")
        XCTAssertEqual(parsed["SUMMARY"]?["Best Share"], "987654321")
    }
    
    func testParsePoolsResponse() {
        let raw = "STATUS=S,When=1705104000,Code=7,Msg=1 Pool(s)|POOL=0,URL=stratum+tcp://solo.ckpool.org:3333,User=bc1qtest.worker,Status=Alive,Priority=0,Accepted=100,Rejected=1|"
        
        let parsed = CGMinerResponseParser.parse(raw)
        
        XCTAssertNotNil(parsed["POOL"])
        XCTAssertEqual(parsed["POOL"]?["URL"], "stratum+tcp://solo.ckpool.org:3333")
        XCTAssertEqual(parsed["POOL"]?["User"], "bc1qtest.worker")
        XCTAssertEqual(parsed["POOL"]?["Status"], "Alive")
    }
    
    func testExtractBracketMetrics() {
        let estatsRaw = "Ver[1292Q-20240116_V4.00a-2019] DNA[APCMB0V01] Elapsed[12345] BOOTBY[0x00] LW[123456] MH[0 0 0] HW[0] DH[0.000%] GHSspd[96557.33] DH[0.000%] Temp[31] TMax[65] TMin[55] TAvg[60] Fan1[2587] Fan2[2600] FanR[89%] Vo[319] PS[0 1215 2428 65 1601 2429 1673] PLL0[1392 1406 1392] PLL1[1392 1392 1392] PLL2[1392 1392 1392] PLL3[1392 1392 1392] GHSmm[97000.00] WU[12500.00] Freq[700] PING[18] WORKMODE[2]"
        
        let metrics = CGMinerResponseParser.extractBracketMetrics(estatsRaw)
        
        // Check various extracted values
        XCTAssertEqual(metrics["Ver"], "1292Q-20240116_V4.00a-2019")
        XCTAssertEqual(metrics["Elapsed"], "12345")
        XCTAssertEqual(metrics["GHSspd"], "96557.33")
        XCTAssertEqual(metrics["Temp"], "31")
        XCTAssertEqual(metrics["TMax"], "65")
        XCTAssertEqual(metrics["TMin"], "55")
        XCTAssertEqual(metrics["TAvg"], "60")
        XCTAssertEqual(metrics["Fan1"], "2587")
        XCTAssertEqual(metrics["Fan2"], "2600")
        XCTAssertEqual(metrics["FanR"], "89%")
        XCTAssertEqual(metrics["PS"], "0 1215 2428 65 1601 2429 1673")
        XCTAssertEqual(metrics["Freq"], "700")
        XCTAssertEqual(metrics["PING"], "18")
        XCTAssertEqual(metrics["WORKMODE"], "2")
        XCTAssertEqual(metrics["GHSmm"], "97000.00")
    }
    
    func testExtractBracketMetricsEmpty() {
        let metrics = CGMinerResponseParser.extractBracketMetrics("")
        XCTAssertTrue(metrics.isEmpty)
    }
    
    func testExtractBracketMetricsNoMatches() {
        let raw = "No brackets here at all"
        let metrics = CGMinerResponseParser.extractBracketMetrics(raw)
        XCTAssertTrue(metrics.isEmpty)
    }
    
    func testParseEmptyResponse() {
        let parsed = CGMinerResponseParser.parse("")
        XCTAssertTrue(parsed.isEmpty)
    }
    
    func testParseVersionResponse() {
        let raw = "STATUS=S,When=1705104000,Code=22,Msg=CGMiner versions|VERSION,CGMiner=4.11.1,API=3.7,Miner=Avalon1066|"
        
        let parsed = CGMinerResponseParser.parse(raw)
        
        XCTAssertNotNil(parsed["VERSION"])
        XCTAssertEqual(parsed["VERSION"]?["CGMiner"], "4.11.1")
        XCTAssertEqual(parsed["VERSION"]?["API"], "3.7")
        XCTAssertEqual(parsed["VERSION"]?["Miner"], "Avalon1066")
    }
    
    // MARK: - JSON Codable Tests (kept for compatibility)
    
    func testCGMinerSummaryResponseDecoding() throws {
        let json = """
        {
            "STATUS": [
                {
                    "STATUS": "S",
                    "When": 1700000000,
                    "Code": 11,
                    "Msg": "Summary",
                    "Description": "cgminer 4.11.1"
                }
            ],
            "SUMMARY": [
                {
                    "Elapsed": 86400,
                    "GHS5s": 105.23,
                    "GHSav": 104.50,
                    "Accepted": 12345,
                    "Rejected": 12,
                    "HardwareErrors": 5,
                    "Stale": 3,
                    "BestShare": 987654321
                }
            ]
        }
        """
        
        let data = Data(json.utf8)
        let response = try JSONDecoder().decode(CGMinerSummaryResponse.self, from: data)
        
        XCTAssertEqual(response.STATUS.count, 1)
        XCTAssertTrue(response.STATUS[0].isSuccess)
        XCTAssertEqual(response.SUMMARY.count, 1)
        
        let summary = response.SUMMARY[0]
        XCTAssertEqual(summary.Elapsed, 86400)
        XCTAssertEqual(summary.GHS5s, 105.23)
        XCTAssertEqual(summary.Accepted, 12345)
        XCTAssertEqual(summary.Rejected, 12)
    }
    
    func testCGMinerPoolsResponseDecoding() throws {
        let json = """
        {
            "STATUS": [
                {
                    "STATUS": "S",
                    "When": 1700000000,
                    "Code": 7,
                    "Msg": "1 Pool(s)",
                    "Description": "cgminer 4.11.1"
                }
            ],
            "POOLS": [
                {
                    "POOL": 0,
                    "URL": "stratum+tcp://solo.ckpool.org:3333",
                    "User": "bc1qexample.worker1",
                    "Status": "Alive",
                    "Priority": 0,
                    "Accepted": 100,
                    "Rejected": 1,
                    "Stale": 0
                }
            ]
        }
        """
        
        let data = Data(json.utf8)
        let response = try JSONDecoder().decode(CGMinerPoolsResponse.self, from: data)
        
        XCTAssertEqual(response.POOLS.count, 1)
        
        let pool = response.POOLS[0]
        XCTAssertEqual(pool.POOL, 0)
        XCTAssertEqual(pool.URL, "stratum+tcp://solo.ckpool.org:3333")
        XCTAssertEqual(pool.User, "bc1qexample.worker1")
        XCTAssertEqual(pool.Status, "Alive")
    }
    
    func testCGMinerStatsResponseDecoding() throws {
        let json = """
        {
            "STATUS": [
                {
                    "STATUS": "S",
                    "When": 1700000000,
                    "Code": 70,
                    "Msg": "CGMiner stats",
                    "Description": "cgminer 4.11.1"
                }
            ],
            "STATS": [
                {
                    "STATS": 0,
                    "ID": "AVA10",
                    "Elapsed": 86400,
                    "Type": "Avalon1066",
                    "Fan1": 3500,
                    "Fan2": 3600,
                    "Fan3": 3550,
                    "Temp1": 65.5,
                    "Temp2": 67.2,
                    "Temp3": 66.0,
                    "Frequency": 600.0,
                    "Voltage": 12.0,
                    "Power": 2850.0,
                    "GHSmm": 105.5,
                    "ASIC": 72
                }
            ]
        }
        """
        
        let data = Data(json.utf8)
        let response = try JSONDecoder().decode(CGMinerStatsResponse.self, from: data)
        
        XCTAssertEqual(response.STATS.count, 1)
        
        let stats = response.STATS[0]
        XCTAssertEqual(stats.ID, "AVA10")
        XCTAssertEqual(stats.deviceType, "Avalon1066")
        XCTAssertEqual(stats.Fan1, 3500)
        XCTAssertEqual(stats.Temp1, 65.5)
        XCTAssertEqual(stats.GHSmm, 105.5)
        XCTAssertEqual(stats.ASIC, 72)
        
        // Test computed properties
        XCTAssertEqual(stats.averageFanSpeed, 3550)
        XCTAssertEqual(stats.averageTemperature, (65.5 + 67.2 + 66.0) / 3.0, accuracy: 0.01)
    }
    
    func testCGMinerVersionResponseDecoding() throws {
        let json = """
        {
            "STATUS": [
                {
                    "STATUS": "S",
                    "When": 1700000000,
                    "Code": 22,
                    "Msg": "CGMiner versions",
                    "Description": "cgminer 4.11.1"
                }
            ],
            "VERSION": [
                {
                    "CGMiner": "4.11.1",
                    "API": "3.7",
                    "Miner": "Avalon1066",
                    "CompileTime": "Jan 01 2024 12:00:00",
                    "Type": "Avalon10"
                }
            ]
        }
        """
        
        let data = Data(json.utf8)
        let response = try JSONDecoder().decode(CGMinerVersionResponse.self, from: data)
        
        XCTAssertEqual(response.VERSION.count, 1)
        
        let version = response.VERSION[0]
        XCTAssertEqual(version.CGMiner, "4.11.1")
        XCTAssertEqual(version.API, "3.7")
        XCTAssertEqual(version.Miner, "Avalon1066")
    }
    
    // MARK: - Client Initialization Tests
    
    func testAvalonClientInitialization() {
        let client = AvalonClient(deviceIpAddress: "192.168.1.100")
        
        XCTAssertEqual(client.deviceIpAddress, "192.168.1.100")
        XCTAssertEqual(client.port, AvalonClient.defaultPort)
        XCTAssertEqual(client.id, "192.168.1.100")
    }
    
    func testAvalonClientCustomPort() {
        let client = AvalonClient(deviceIpAddress: "192.168.1.100", port: 4029)
        
        XCTAssertEqual(client.port, 4029)
    }
    
    func testAnyCodableValue() throws {
        // Test string
        let stringJson = "\"hello\""
        let stringValue = try JSONDecoder().decode(AnyCodableValue.self, from: Data(stringJson.utf8))
        if case .string(let s) = stringValue {
            XCTAssertEqual(s, "hello")
        } else {
            XCTFail("Expected string value")
        }
        
        // Test int
        let intJson = "42"
        let intValue = try JSONDecoder().decode(AnyCodableValue.self, from: Data(intJson.utf8))
        if case .int(let i) = intValue {
            XCTAssertEqual(i, 42)
        } else {
            XCTFail("Expected int value")
        }
        
        // Test bool
        let boolJson = "true"
        let boolValue = try JSONDecoder().decode(AnyCodableValue.self, from: Data(boolJson.utf8))
        if case .bool(let b) = boolValue {
            XCTAssertTrue(b)
        } else {
            XCTFail("Expected bool value")
        }
    }
    
    // MARK: - Hash Rate Calculation Tests
    
    func testHashRateConversion() {
        // Test that MHS values are correctly converted to GH/s
        // MHS av = 105,230,000 MH/s = 105,230 GH/s = 105.23 TH/s
        let mhsValue = 105230000.0
        let ghsValue = mhsValue / 1000.0  // Convert to GH/s
        XCTAssertEqual(ghsValue, 105230.0, accuracy: 0.01)
        
        let thsValue = ghsValue / 1000.0  // Convert to TH/s
        XCTAssertEqual(thsValue, 105.23, accuracy: 0.01)
    }
    
    func testPowerExtractionFromPS() {
        // PS field format: PS[0 1215 2428 65 1601 2429 1673]
        // Last value is the power in watts
        let psRaw = "0 1215 2428 65 1601 2429 1673"
        let parts = psRaw.split(separator: " ")
        let power = Double(parts.last ?? "") ?? 0
        XCTAssertEqual(power, 1673.0)
    }
}
