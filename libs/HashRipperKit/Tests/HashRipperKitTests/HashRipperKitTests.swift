//
//  HashRipperKitTests.swift
//  HashRipperKit
//

import Testing
@testable import HashRipperKit

@Test func testMinerTypeFromBoardVersion() async throws {
    #expect(MinerType.from(boardVersion: "200", deviceModel: nil) == .BitaxeUltra)
    #expect(MinerType.from(boardVersion: "400", deviceModel: nil) == .BitaxeSupra)
    #expect(MinerType.from(boardVersion: "600", deviceModel: nil) == .BitaxeGamma)
    #expect(MinerType.from(boardVersion: "800", deviceModel: nil) == .BitaxeGammaTurbo)
}

@Test func testMinerTypeFromDeviceModel() async throws {
    #expect(MinerType.from(boardVersion: nil, deviceModel: "NerdQAxe+") == .NerdQAxePlus)
    #expect(MinerType.from(boardVersion: nil, deviceModel: "NerdQAxe++") == .NerdQAxePlusPlus)
    #expect(MinerType.from(boardVersion: nil, deviceModel: "NerdQX") == .NerdQX)
}

@Test func testHashRateFormatting() async throws {
    // API returns values in GH/s
    // 6.5 from API = 6.5 GH/s
    let ghs = formatMinerHashRate(rawRateValue: 6.5)
    #expect(ghs.rateSuffix == "GH/s")
    #expect(ghs.rateString == "6.50")
    
    // 1500 from API = 1500 GH/s = 1.5 TH/s
    let ths = formatMinerHashRate(rawRateValue: 1500)
    #expect(ths.rateSuffix == "TH/s")
    #expect(ths.rateString == "1.50")
    
    // Zero should return 0 GH/s
    let zero = formatMinerHashRate(rawRateValue: 0)
    #expect(zero.rateSuffix == "GH/s")
    #expect(zero.rateString == "0")
}

