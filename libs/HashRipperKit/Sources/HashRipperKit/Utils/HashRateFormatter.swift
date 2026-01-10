//
//  HashRateFormatter.swift
//  HashRipperKit
//
//  Cross-platform hash rate formatting utility
//

import Foundation

private let suffixes = ["H/s", "KH/s", "MH/s", "GH/s", "TH/s", "PH/s", "EH/s"]

public struct FormattedHashRate {
    public let rateString: String
    public let rateSuffix: String
    public let rawValue: Double
    
    public var combined: String {
        "\(rateString) \(rateSuffix)"
    }
}

/// Format a raw hash rate value from the AxeOS API to a human-readable string
/// Note: The API returns hash rate in GH/s, so we multiply by 1 billion to get H/s
/// - Parameter rawRateValue: Hash rate as returned by the API (in GH/s)
/// - Returns: Formatted hash rate with appropriate unit suffix
public func formatMinerHashRate(rawRateValue: Double) -> FormattedHashRate {
    if rawRateValue == 0 {
        return FormattedHashRate(rateString: "0", rateSuffix: "GH/s", rawValue: 0)
    }
    
    // API returns value in GH/s, convert to H/s for calculation
    let rateInHashPerSecond = rawRateValue * 1_000_000_000
    
    // Determine the "power of 1000" to scale by
    let power = max(0, min(suffixes.count - 1, Int(floor(log10(rateInHashPerSecond) / 3.0))))
    
    // Apply the scaling factor
    let scaledValue = rateInHashPerSecond / pow(1000.0, Double(power))
    
    // Determine decimal places based on magnitude
    let decimals: Int
    if scaledValue < 10 {
        decimals = 2
    } else if scaledValue < 100 {
        decimals = 1
    } else {
        decimals = 0
    }
    
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.maximumFractionDigits = decimals
    formatter.minimumFractionDigits = decimals
    
    let stringValue = formatter.string(from: NSNumber(value: scaledValue)) ?? String(format: "%.\(decimals)f", scaledValue)
    
    return FormattedHashRate(
        rateString: stringValue,
        rateSuffix: suffixes[power],
        rawValue: rawRateValue
    )
}

