//
//  FlashMinerSettings.swift
//  HashRipper
//
//  Created by Matt Sellars
//

import SwiftData
import SwiftUI
import AxeOSClient

import SwiftUI

/// UI state for a single step
private enum StepStatus {
    case idle, inProgress, success, failure
}

struct FlashMinerSettings: View {
    @Environment(\.modelContext) var modelContext

    let isNewMinerSetup: Bool

    // Dependencies
    let client: AxeOSClient
    let settings: MinerSettings

    // UI state
    @State private var updateStatus:  StepStatus = .idle
    @State private var restartStatus: StepStatus = .idle
    @State private var isRunning = false           // overall spinner flag

    @Environment(\.dismiss) private var dismiss    // for "Done" or "Cancel"

    // MARK:‑ Body
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // 1️⃣ Checklist
            checklist

            // 2️⃣ Bottom‑bar buttons
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .opacity(allSucceeded ? 0 : 1)
                    .animation(.easeOut, value: allSucceeded)
                Spacer().frame(width: 24)
                    .opacity(allSucceeded ? 0 : 1)
                    .animation(.easeOut, value: allSucceeded)
                if isRunning {
//                    ProgressView()       // overall spinner
                } else if allSucceeded {
                    Button("Done") { dismiss() }
                } else {
                    Button("Retry") { runSteps() }
                }
                Spacer()
            }
        }
        .padding()
        .onAppear(perform: runSteps)
    }
}

// MARK: ‑ Private helpers
private extension FlashMinerSettings {
    // Creates the checklist rows
    var checklist: some View {
        VStack(alignment: .leading, spacing: 12) {
            checklistRow(
                title: "Update miner settings",
                status: updateStatus)

            checklistRow(
                title: "Restart miner",
                status: restartStatus)
        }
    }

    @ViewBuilder
    func checklistRow(title: String, status: StepStatus) -> some View {
        HStack {
            icon(for: status)
            Text(title)
        }
    }

    @ViewBuilder
    func icon(for status: StepStatus) -> some View {
        switch status {
        case .idle:
            Image(systemName: "arrow.forward.circle.dotted")
                .opacity(0.7)
        case .inProgress:
            Image(systemName: "arrow.forward.circle")
//                .frame(width: 20)  // keep width stable
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failure:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
        }
    }

    var allSucceeded: Bool {
        updateStatus == .success && restartStatus == .success
    }

    /// Runs the two steps serially
    func runSteps() {
        guard !isRunning else { return }
        isRunning = true
        updateStatus = .idle
        restartStatus = .idle

        // Capture values for use in task
        let settingsCopy = settings
        let clientCopy = client

        Task {
            try? await Task.sleep(for: .seconds(0.15))
            await MainActor.run {
                self.updateStatus = .inProgress
            }
            
            // STEP 1 – update settings
            switch await clientCopy.updateSystemSettings(settings: settingsCopy) {
            case .success(true):
                await MainActor.run {
                    self.updateStatus = .success
                }
            default:
                await MainActor.run {
                    self.updateStatus = .failure
                    self.isRunning = false
                }
                return                               // stop – show Retry
            }

            // STEP 2 – restart
            await MainActor.run {
                self.restartStatus = .inProgress
            }
            
            // ⏱ 500 ms pause
            try? await Task.sleep(for: .seconds(0.25))
            switch await clientCopy.restartClient() {
            case .success(true):
                await MainActor.run {
                    self.restartStatus = .success
                }
            default:
                await MainActor.run {
                    self.restartStatus = .failure
                }
            }
            await MainActor.run {
                self.isRunning = false
            }
        }
    }
}
