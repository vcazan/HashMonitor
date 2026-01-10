//
//  StatusBarPopoverView.swift
//  HashRipper
//
//  Created by Matt Sellars
//

import SwiftUI
import SwiftData

struct StatusBarPopoverView: View {
    @ObservedObject var manager: StatusBarManager
    @Environment(\.openWindow) private var openWindow
    @Environment(\.modelContext) private var modelContext
    @Query private var allMiners: [Miner]
    @Query(
        filter: #Predicate<WatchDogActionLog> { !$0.isRead },
        sort: [SortDescriptor<WatchDogActionLog>(\.timestamp, order: .reverse)]
    ) private var unreadActions: [WatchDogActionLog]

    @State private var topMiners: [TopMinerData] = []

    struct TopMinerData: Identifiable {
        var id: String {
            miner.macAddress
        }
        let miner: Miner
        let bestDiff: String
        let bestDiffValue: Double
    }

    @Environment(\.colorScheme) private var colorScheme
    
    private var hasOfflineMiners: Bool {
        manager.activeMiners < manager.minerCount
    }
    
    private var offlineCount: Int {
        manager.minerCount - manager.activeMiners
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Alert banner if miners are offline
            if hasOfflineMiners && manager.minerCount > 0 {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                    Text("\(offlineCount) miner\(offlineCount == 1 ? "" : "s") offline")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.red)
            }
            
            // Main content
            VStack(spacing: 16) {
                // Hash Rate - primary metric
                VStack(spacing: 4) {
                    Text(formatHashRate(manager.totalHashRate))
                        .font(.system(size: 36, weight: .semibold, design: .rounded))
                    Text("total hash rate")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
                
                // Secondary stats row
                HStack(spacing: 0) {
                    VStack(spacing: 2) {
                        Text(formatPower(manager.totalPower))
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                        Text("power")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                    
                    Rectangle()
                        .fill(Color.secondary.opacity(0.2))
                        .frame(width: 1, height: 28)
                    
                    VStack(spacing: 2) {
                        HStack(spacing: 4) {
                            Text("\(manager.activeMiners)")
                                .font(.system(size: 15, weight: .medium, design: .rounded))
                                .foregroundStyle(hasOfflineMiners ? .primary : .primary)
                            Text("/")
                                .font(.system(size: 13))
                                .foregroundStyle(.tertiary)
                            Text("\(manager.minerCount)")
                                .font(.system(size: 15, weight: .medium, design: .rounded))
                                .foregroundStyle(hasOfflineMiners ? .red : .primary)
                        }
                        Text("miners")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.vertical, 12)
                .background(colorScheme == .dark ? Color(white: 0.08) : Color(white: 0.95))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .padding(16)
            
            // WatchDog activity banner (if any unread actions)
            if !unreadActions.isEmpty {
                Button {
                    openMainWindow()
                    NotificationCenter.default.post(name: .showAlertsTab, object: nil)
                    manager.popover?.performClose(nil)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "shield.checkered")
                            .font(.system(size: 10))
                        Text("\(unreadActions.count) WatchDog action\(unreadActions.count == 1 ? "" : "s")")
                            .font(.system(size: 11, weight: .medium))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .medium))
                    }
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.orange.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
            
            // Footer
            HStack(spacing: 8) {
                Button {
                    openMainWindow()
                } label: {
                    Text("Open")
                        .font(.system(size: 11, weight: .medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                Button {
                    NotificationCenter.default.post(name: .refreshMinerStats, object: nil)
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
        }
        .frame(width: 220)
    }

    private func openMainWindow() {
        print("🪟 StatusBarPopoverView.openMainWindow() called")

        // Close the popover first
        if let popover = manager.popover {
            popover.performClose(nil)
        }

        // Activate the app
        NSApp.activate(ignoringOtherApps: true)

        // First try to find existing visible main window
        var foundExistingWindow = false
        print("🪟 Checking \(NSApp.windows.count) total windows")

        for window in NSApp.windows {
            let className = NSStringFromClass(type(of: window))
            print("🪟 Window: \(className), title: '\(window.title)', visible: \(window.isVisible), canBecomeKey: \(window.canBecomeKey), miniaturized: \(window.isMiniaturized)")

            // Skip system windows and popover windows
            if className.contains("StatusBar") ||
               className.contains("MenuBar") ||
               className.contains("Popover") ||
               window.title.contains("Settings") ||
               window.title.contains("Downloads") ||
               window.title.contains("WatchDog") ||
               window.title.contains("Firmware") {
                print("🪟 Skipping system window: \(className)")
                continue
            }

            // Look for visible main app window - must have HashWatcher title specifically
            if window.canBecomeKey &&
               window.isVisible &&
               !window.isMiniaturized &&
               (window.title == "HashWatcher" || window.title == "HashRipper") {
                print("🪟 Found existing visible main window: \(className), title: '\(window.title)'")
                print("🪟 Window frame: \(window.frame)")
                print("🪟 Window level: \(window.level)")
                window.makeKeyAndOrderFront(nil)
                foundExistingWindow = true
                break
            }
        }

        if !foundExistingWindow {
            print("🪟 No existing main window found, opening via manager")
            // Use the StatusBarManager which has logic to trigger Window menu
            manager.openMainWindow()

            // Restore window size if we have one saved
            if let savedFrame = manager.savedWindowFrame {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.restoreWindowFrame(savedFrame)
                }
            }
        }
    }

    private func restoreWindowFrame(_ frame: NSRect) {
        // Find the newly created main window and restore its frame
        for window in NSApp.windows {
            let className = NSStringFromClass(type(of: window))

            if !className.contains("StatusBar") &&
               !className.contains("MenuBar") &&
               !window.title.contains("Settings") &&
               !window.title.contains("Downloads") &&
               !window.title.contains("WatchDog") &&
               !window.title.contains("Firmware") &&
               window.canBecomeKey &&
               window.isVisible {

                print("🪟 Restoring window frame to: \(frame)")
                window.setFrame(frame, display: true)
                window.makeKeyAndOrderFront(nil)
                break
            }
        }
    }

    private func formatHashRate(_ hashRate: Double) -> String {
        let formatted = formatMinerHashRate(rawRateValue: hashRate)
        return "\(formatted.rateString) \(formatted.rateSuffix)"
    }

    private func formatPower(_ power: Double) -> String {
        if power >= 1000 {
            return String(format: "%.2f kW", power / 1000)
        } else if power > 0 {
            return String(format: "%.0f W", power)
        } else {
            return "0 W"
        }
    }

    private func rankColor(for index: Int) -> Color {
        switch index {
        case 0: return .yellow  // Gold
        case 1: return .gray    // Silver
        case 2: return .brown   // Bronze
        default: return .blue
        }
    }

    private func checkAndUpdateIfNeeded(for macAddress: String) {
        Task { @MainActor in
            // Find the miner that was updated
            guard let updatedMiner = allMiners.first(where: { $0.macAddress == macAddress }) else { return }

            // Get the latest update for this miner
            guard let latestUpdate = updatedMiner.getLatestUpdate(from: modelContext),
                  let bestDiff = latestUpdate.bestDiff,
                  !bestDiff.isEmpty && bestDiff != "N/A" else { return }

            let bestDiffValue = DifficultyParser.parseDifficultyValue(bestDiff)
            guard bestDiffValue > 0 else { return }

            // Check if this miner is already in the top 3
            let isAlreadyInTop3 = topMiners.contains { $0.miner.macAddress == macAddress }

            if isAlreadyInTop3 {
                // If already in top 3, always reload to update the value
                loadTopMiners()
                return
            }

            // If we have less than 3 miners, always add new ones
            if topMiners.count < 3 {
                loadTopMiners()
                return
            }

            // Check if this new value would beat the 3rd place (lowest of top 3)
            let lowestTop3Value = topMiners.last?.bestDiffValue ?? 0
            if bestDiffValue > lowestTop3Value {
                loadTopMiners()
            }
        }
    }

    private func loadTopMiners() {
        Task { @MainActor in

            var minerDataArray: [TopMinerData] = []

            for miner in allMiners {
                // Get the latest update for this miner using the existing extension
                if let latestUpdate = miner.getLatestUpdate(from: modelContext) {
                    if let bestDiff = latestUpdate.bestDiff,
                       !bestDiff.isEmpty && bestDiff != "N/A" {

                        let bestDiffValue = DifficultyParser.parseDifficultyValue(bestDiff)
                        if bestDiffValue > 0 {
                            minerDataArray.append(TopMinerData(
                                miner: miner,
                                bestDiff: bestDiff,
                                bestDiffValue: bestDiffValue
                            ))

                        }
                    }
                }
            }

            // Sort by bestDiffValue in descending order and take top 3
            let top3 = Array(minerDataArray.sorted { $0.bestDiffValue > $1.bestDiffValue }.prefix(3))

            withAnimation {
                topMiners = top3
            }
        }
    }

}

// Notification name for refresh action
extension Notification.Name {
    static let refreshMinerStats = Notification.Name("refreshMinerStats")
    static let showAlertsTab = Notification.Name("showAlertsTab")
}
