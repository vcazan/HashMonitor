//
//  HashOpsToolbarItems.swift
//  HashRipper
//
//  Created by Matt Sellars
//

import SwiftUI
import SwiftData

struct HashOpsToolbarItems: View {
    @Environment(\.newMinerScanner) private var deviceRefresher
    @Environment(\.minerClientManager) private var minerClientManager

    var addNewMiner: () -> Void
    var addMinerManually: () -> Void
    var rolloutProfile: () -> Void
    
    var body: some View {
        HStack {
            Menu {
            Button(action: addNewMiner) {
                    Label("Setup New Miner (AP Mode)", systemImage: "wifi.circle")
                }
                Button(action: addMinerManually) {
                    Label("Add by IP Address", systemImage: "network")
                }
            } label: {
                Image(systemName: "plus.rectangle.portrait")
            }
            .help("Add a new miner")
            
            
            if (self.minerClientManager?.isPaused ?? false) {
                Button(action: resumeMinerStatsUpdates) {
                    Image(systemName: "play.circle")
                }
                .help("Resume miner stats updates")
            } else {
                Button(action: pauseMinerStatsUpdates) {
                    Image(systemName:"pause.circle")
                }
                .help("Pause miner stats updates")
            }
            
            
            Button(action: refreshMiners) {
                Image(systemName: "arrow.clockwise.circle")
            }
            .help("Refresh miner stats now")
            
            Button(action: scanForNewMiners) {
                Image(systemName: "badge.plus.radiowaves.right")
            }
            .help("Scan for new miners")
            .disabled(deviceRefresher?.isScanning ?? false)
            
            
            Button(action: rolloutProfile) {
                Image(systemName: "iphone.and.arrow.forward.inward")
            }
            .help("Deploy a miner profile to your miners")
        }
    }

    private func refreshMiners() {
        minerClientManager?.refreshClientInfo()
    }

    private func pauseMinerStatsUpdates() {
        self.minerClientManager?.pauseMinerUpdates()
    }

    private func resumeMinerStatsUpdates() {
        self.minerClientManager?.resumeMinerUpdates()
    }

    private func scanForNewMiners() {
        Task {
            await self.deviceRefresher?.rescanDevicesStreaming()
        }
    }
}
