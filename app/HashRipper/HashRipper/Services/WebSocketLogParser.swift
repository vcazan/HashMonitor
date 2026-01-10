//
//  WebSocketLogParser.swift
//  HashRipper
//
//  Created by Claude Code
//

import Foundation
import OSLog

actor WebSocketLogParser {
    // Pattern with ANSI color codes: [0;32mI (12345) component: message[0m
    private static let ansiPattern = #"\[([0-9;]+)m([A-Z]) \((\d+)\) ([^:]+): (.+)\[0m"#
    private static let ansiRegex = try! NSRegularExpression(pattern: ansiPattern)
    
    // Plain text pattern: I (12345) component: message
    private static let plainPattern = #"^([A-Z]) \((\d+)\) ([^:]+): (.+)$"#
    private static let plainRegex = try! NSRegularExpression(pattern: plainPattern)

    func parse(_ rawText: String) -> WebSocketLogEntry? {
        // Try ANSI pattern first
        if let entry = parseAnsi(rawText) {
            return entry
        }
        
        // Fall back to plain text pattern
        if let entry = parsePlain(rawText) {
            return entry
        }
        
        // Silently ignore unparseable lines (don't log to console)
        return nil
    }
    
    private func parseAnsi(_ rawText: String) -> WebSocketLogEntry? {
        let nsString = rawText as NSString
        guard let match = Self.ansiRegex.firstMatch(
            in: rawText,
            range: NSRange(location: 0, length: nsString.length)
        ), match.numberOfRanges == 6 else {
            return nil
        }

        let ansiColorCode = nsString.substring(with: match.range(at: 1))
        let levelChar = nsString.substring(with: match.range(at: 2))
        let timestampStr = nsString.substring(with: match.range(at: 3))
        let componentStr = nsString.substring(with: match.range(at: 4))
        let message = nsString.substring(with: match.range(at: 5))

        // Extract color code number from ANSI sequence (e.g., "0;32" → 32)
        let colorCode: Int
        let parts = ansiColorCode.split(separator: ";")
        if parts.count == 2, let code = Int(parts[1]) {
            colorCode = code
        } else {
            colorCode = 37  // Default to white
        }

        guard let timestamp = TimeInterval(timestampStr),
              let level = WebSocketLogEntry.LogLevel(rawValue: levelChar) else {
            return nil
        }

        let component = WebSocketLogEntry.LogComponent(from: componentStr)

        return WebSocketLogEntry(
            id: UUID(),
            timestamp: timestamp,
            level: level,
            component: component,
            message: message,
            rawText: rawText,
            ansiColorCode: ansiColorCode,
            colorCode: colorCode,
            receivedAt: Date()
        )
    }
    
    private func parsePlain(_ rawText: String) -> WebSocketLogEntry? {
        let nsString = rawText as NSString
        guard let match = Self.plainRegex.firstMatch(
            in: rawText,
            range: NSRange(location: 0, length: nsString.length)
        ), match.numberOfRanges == 5 else {
            return nil
        }

        let levelChar = nsString.substring(with: match.range(at: 1))
        let timestampStr = nsString.substring(with: match.range(at: 2))
        let componentStr = nsString.substring(with: match.range(at: 3))
        let message = nsString.substring(with: match.range(at: 4))

        guard let timestamp = TimeInterval(timestampStr),
              let level = WebSocketLogEntry.LogLevel(rawValue: levelChar) else {
            return nil
        }

        let component = WebSocketLogEntry.LogComponent(from: componentStr)
        
        // Infer color code from level
        let colorCode = level.colorCode

        return WebSocketLogEntry(
            id: UUID(),
            timestamp: timestamp,
            level: level,
            component: component,
            message: message,
            rawText: rawText,
            ansiColorCode: "0;\(colorCode)",
            colorCode: colorCode,
            receivedAt: Date()
        )
    }
}

fileprivate extension Logger {
    static let parserLogger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "HashRipper",
        category: "WebSocketLogParser"
    )
}
