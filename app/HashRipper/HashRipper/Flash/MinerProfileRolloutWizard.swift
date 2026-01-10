//
//  MinerProfileRolloutWizard.swift
//  HashRipper
//
//  Created by Matt Sellars
//

import SwiftUI
import SwiftData
import AxeOSClient

enum RolloutStatus: Equatable {
    case pending(step: Float, total: Float)
    case complete
    case failed

    static func == (lhs: RolloutStatus, rhs: RolloutStatus) -> Bool {
        switch (lhs, rhs) {
        case (.pending(let l, let r), .pending(let s, let t)):
            return l == s && r == t
        case (.complete, .complete), (.failed, .failed):
            return true
        default:
            return false
        }
    }
}

enum Stage: Int {
    case one = 1
    case two = 2
    case three = 3

    func previous() -> Stage {
        switch self {
        case .one:
            return .one
        case .two:
            return .one
        case .three:
            return .two
        }
    }

    func next() -> Stage {
        switch self {
        case .one:
            return .two
        case .two:
            return .three
        case .three:
            return .three
        }
    }
}
// MARK: – View-model ----------------------------------------------------------

class MinerRolloutState: Identifiable {
    var id: String {
        miner.ipAddress
    }
    let miner: Miner
    var status: RolloutStatus

    init(miner: Miner, status: RolloutStatus = .pending(step: 0, total: 2)) {
        self.miner = miner
        self.status = status
    }
}

@Observable
final class RolloutWizardModel {
    var pageViewModel = PageIndicatorViewModel(totalPages: 3)
    // page index (0-based)
    var stage: Stage = .one

    // data
    var selectedProfile: MinerProfileTemplate? = nil
    var selectedMiners: [IPAddress : MinerRolloutState] = [:]

    var clientManager: MinerClientManager? = nil
    var rolloutInProgress = false

    func nextPage() {
        self.stage = self.stage.next()
        pageViewModel.nextPage()
    }

    func previousPage() {
        self.stage = self.stage.previous()
        pageViewModel.previousPage()
    }

    var stageTitle: String {
        switch stage {
        case .one:      return "Select Profile"
        case .two:      return "Select Miners"
        case .three:    return "Deploying profile"
        }
    }

    // Start the rollout once we reach page 3
    @MainActor
    func beginRollout() {
        guard rolloutInProgress == false else {
            print("Prevented double run of rollout")
            return
        }
        rolloutInProgress = true

        print("BEGIN ROLLOUT CALLED!")

        let allMiners = selectedMiners.values.filter({ $0.status != .complete }).map( \.miner )
        guard let profile = selectedProfile, let clientManager = clientManager else {
            allMiners.forEach { miner in
                selectedMiners[miner.ipAddress] = .init(miner: miner, status: .failed)
            }
            return
        }

        let clientAndSettingsCollection = allMiners.map { miner in
            let hasFallbackStratumData = profile.fallbackStratumAccount != nil && profile.fallbackStratumPassword != nil && profile.fallbackStratumPort != nil && profile.fallbackStratumURL != nil
            let stratumUser = profile.minerUserSettingsString(minerName: miner.hostName)
            let fallbackStratumUser = profile.fallbackMinerUserSettingsString(minerName: miner.hostName)

            let settings = MinerSettings(
                stratumURL: profile.stratumURL,
                fallbackStratumURL: hasFallbackStratumData ? profile.fallbackStratumURL! : nil,
                stratumUser: stratumUser,
                stratumPassword: profile.stratumPassword,
                fallbackStratumUser: fallbackStratumUser,
                fallbackStratumPassword: hasFallbackStratumData ? profile.fallbackStratumPassword : nil,
                stratumPort: profile.stratumPort,
                fallbackStratumPort: hasFallbackStratumData ? profile.fallbackStratumPort : nil,
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
            let client = clientManager.client(forIpAddress: miner.ipAddress) ?? AxeOSClient(deviceIpAddress: miner.ipAddress, urlSession: URLSession.shared)
            return (client, settings)
        }
        Task.detached {
            await withTaskGroup(of: Result<IPAddress, MinerUpdateError>.self) { group in
                clientAndSettingsCollection.forEach { clientAndSetting in
                    group.addTask {
                        let client = clientAndSetting.0
                        let settings = clientAndSetting.1
                        Task.detached { @MainActor in
                            if let state = self.selectedMiners[client.deviceIpAddress] {
                                withAnimation {
                                    self.selectedMiners[client.deviceIpAddress] = MinerRolloutState(miner: state.miner, status: .pending(step: 0.1, total: 2))
                                }
                            }
                        }
                        try? await Task.sleep(for: .seconds(0.35))
                        switch await client.updateSystemSettings(settings: settings) { // send settings
                        case .success:
                            Task.detached { @MainActor in
                                if let state = self.selectedMiners[client.deviceIpAddress] {
                                    withAnimation {
                                        self.selectedMiners[client.deviceIpAddress] = MinerRolloutState(miner: state.miner, status: .pending(step: 1, total: 2))
                                    }
                                }
                            }
                            try? await Task.sleep(for: .seconds(0.35)) // give the miner a moment to handle next request
                            switch await client.restartClient() {
                            case .success:
                                Task.detached { @MainActor in
                                    if let state = self.selectedMiners[client.deviceIpAddress] {
                                        withAnimation {
                                            self.selectedMiners[client.deviceIpAddress] = MinerRolloutState(miner: state.miner, status: .pending(step: 2, total: 2))
                                        }
                                    }
                                }
                                try? await Task.sleep(for: .seconds(0.5)) // give the miner a moment to handle next request
                                return .success(client.deviceIpAddress)
                            case let .failure(error):
                                return .failure(MinerUpdateError.failedRestart(client.deviceIpAddress, error))
                            }

                        case let .failure(error):
                            return .failure(MinerUpdateError.failedUpdate(client.deviceIpAddress, error))
                        }
                    }
                }

                for await clientUpdate in group {
                    switch clientUpdate {
                    case let .success(ipAddress):
                        Task.detached { @MainActor in
                            if let state = self.selectedMiners[ipAddress] {
                                self.selectedMiners[ipAddress] = MinerRolloutState(miner: state.miner, status: .complete)
                            }
                        }
                    case let .failure(.failedRestart(ipAddress, error)):
                        print("Deploying profile to miner at \(ipAddress) due to: \(String(describing: error))")
                        Task.detached { @MainActor in
                            if let state = self.selectedMiners[ipAddress] {
                                self.selectedMiners[ipAddress] = MinerRolloutState(miner: state.miner, status: .failed)
                            }
                        }
                    case let .failure(.failedUpdate(ipAddress, error)):
                        print("Faield to restart miner at \(ipAddress) due to: \(String(describing: error))")
                        Task.detached { @MainActor in
                            if let state = self.selectedMiners[ipAddress] {
                                self.selectedMiners[ipAddress] = MinerRolloutState(miner: state.miner, status: .failed)
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: – Wizard root view ----------------------------------------------------

struct MinerProfileRolloutWizard: View {
    @Environment(\.minerClientManager) var clientManager
    @Environment(\.colorScheme) var colorScheme

    @State private var model: RolloutWizardModel = .init()
    @State private var hasInitialized = false
    
    private var onClose: () -> Void
    private var preSelectedProfile: MinerProfileTemplate?

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
        self.preSelectedProfile = nil
    }

    init(onClose: @escaping () -> Void, profile: MinerProfileTemplate? = nil) {
        self.onClose = onClose
        self.preSelectedProfile = profile
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 6) {
                Text(model.stageTitle)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.primary)
                
                Text(headerSubtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 28)
            .padding(.bottom, 20)
            
            // Step indicator - show 2 steps if profile pre-selected, otherwise 3
            StepIndicatorView(
                currentStep: preSelectedProfile != nil ? model.stage.rawValue - 1 : model.stage.rawValue,
                totalSteps: preSelectedProfile != nil ? 2 : 3
            )
            .padding(.bottom, 20)
            
            Divider()
            
            // Content
            Group {
                switch model.stage {
                case .one:
                    SelectProfileScreen(model: model)
                case .two:
                    SelectMinersScreen(model: model)
                case .three:
                    RolloutStatusScreen(model: model)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeInOut(duration: 0.2), value: model.stage)
            
            Divider()
            
            // Footer
            HStack(spacing: 12) {
                if model.stage.rawValue < Stage.three.rawValue {
                    Button("Cancel") { onClose() }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    
                    Button("Back") { onPrevious() }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .disabled(model.stage == .one || (preSelectedProfile != nil && model.stage == .two))
                    
                    Spacer()
                    
                    Button(action: onNext) {
                        Text("Next")
                            .frame(minWidth: 80)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(nextDisabled)
                    .keyboardShortcut(.defaultAction)
                } else {
                    if model.selectedMiners.values.first(where: { $0.status == .failed }) != nil {
                        Button("Retry Failed") {
                            model.rolloutInProgress = false
                            model.beginRollout()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }
                    
                    Spacer()
                    
                    Button(action: onClose) {
                        Text(allComplete ? "Done" : "Close")
                            .frame(minWidth: 80)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(hasMinersInProgress)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: model.stage) { _, newValue in
            if newValue == .three { model.beginRollout() }
        }
        .onAppear {
            // If a profile was pre-selected, skip to miner selection
            if !hasInitialized, let profile = preSelectedProfile {
                hasInitialized = true
                model.selectedProfile = profile
                model.nextPage()
            }
        }
        .frame(width: 700, height: 650)
    }
    
    private var headerSubtitle: String {
        switch model.stage {
        case .one, .two:
            return "Deploy a profile to your miners to quickly switch pool configurations"
        case .three:
            return "Deploying profile to selected miners..."
        }
    }
    
    private var allComplete: Bool {
        model.selectedMiners.values.allSatisfy { $0.status == .complete }
    }
    
    private var hasMinersInProgress: Bool {
        model.selectedMiners.values.contains { state in
            if case .pending = state.status { return true }
            return false
        }
    }
    
    func onNext() {
        model.nextPage()
        model.clientManager = clientManager
    }

    func onPrevious() {
        model.previousPage()
        model.clientManager = clientManager
    }
    
    private var nextDisabled: Bool {
        switch model.stage {
        case .one: return model.selectedProfile == nil
        case .two: return model.selectedMiners.isEmpty
        default: return true
        }
    }
}

// MARK: - Step Indicator

private struct StepIndicatorView: View {
    let currentStep: Int
    let totalSteps: Int
    
    var body: some View {
        HStack(spacing: 8) {
            ForEach(1...totalSteps, id: \.self) { step in
                Circle()
                    .fill(step <= currentStep ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 8, height: 8)
                    .animation(.easeInOut(duration: 0.2), value: currentStep)
            }
        }
    }
}

// MARK: – Screen 1 · profile selection

private struct SelectProfileScreen: View {
    @Environment(\.modelContext) var modelContext
    @Environment(\.colorScheme) var colorScheme

    @Query(sort: [SortDescriptor(\MinerProfileTemplate.name)])
    var minerProfiles: [MinerProfileTemplate]

    @State var model: RolloutWizardModel

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Label("Available Profiles", systemImage: "square.stack.3d.up")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                
                Spacer()
                
                Text("\(minerProfiles.count) profiles")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }
            .padding(.bottom, 12)
            
            if minerProfiles.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "square.stack.3d.up.slash")
                        .font(.system(size: 32))
                        .foregroundStyle(.tertiary)
                    Text("No profiles available")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                    Text("Create a profile in the Profiles tab first")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(minerProfiles) { profile in
                            ProfileSelectionRow(
                                profile: profile,
                                isSelected: model.selectedProfile?.id == profile.id
                            ) {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    model.selectedProfile = profile
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }
}

// MARK: - Profile Selection Row

private struct ProfileSelectionRow: View {
    let profile: MinerProfileTemplate
    let isSelected: Bool
    let onTap: () -> Void
    
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                // Selection indicator
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary.opacity(0.5))
                
                // Profile icon
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.blue)
                    .frame(width: 36, height: 36)
                    .background(Color.blue.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                
                // Profile details
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(profile.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.primary)
                        
                        Spacer()
                        
                        if profile.fallbackStratumURL != nil {
                            Text("Fallback ✓")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.green)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.1))
                                .clipShape(Capsule())
                        }
                    }
                    
                    HStack(spacing: 16) {
                        HStack(spacing: 4) {
                            Image(systemName: "server.rack")
                                .font(.system(size: 10))
                            Text(profile.stratumURL)
                                .lineLimit(1)
                        }
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        
                        HStack(spacing: 4) {
                            Image(systemName: "number")
                                .font(.system(size: 10))
                            Text("\(profile.stratumPort)")
                        }
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                isSelected
                    ? Color.accentColor.opacity(colorScheme == .dark ? 0.15 : 0.08)
                    : (colorScheme == .dark ? Color(white: 0.12) : Color(white: 0.97))
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.accentColor.opacity(0.5) : Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: – Screen 2 · miner selection

private struct SelectMinersScreen: View {
    @Environment(\.minerClientManager) var minerClientManager
    @Environment(\.colorScheme) var colorScheme

    @Query(sort: [SortDescriptor(\Miner.hostName)])
    var allMiners: [Miner]

    @State var model: RolloutWizardModel

    let columns = [
        GridItem(.adaptive(minimum: 180, maximum: 220)),
    ]

    // Filter out offline miners (computed property, can't use in @Query predicate)
    private var miners: [Miner] {
        allMiners.filter { !$0.isOffline }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Selected profile summary
            if let profile = model.selectedProfile {
                ProfileSummaryCard(profile: profile)
                    .padding(.bottom, 20)
            }
            
            // Miners header
            HStack {
                Label("Select Miners", systemImage: "cpu")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                
                Text("\(model.selectedMiners.count) selected")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.1))
                    .clipShape(Capsule())
                
                Spacer()
                
                Button(model.selectedMiners.count == miners.count ? "Deselect All" : "Select All") {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        if model.selectedMiners.count == miners.count {
                            miners.forEach { model.selectedMiners[$0.ipAddress] = nil }
                        } else {
                            miners.forEach { model.selectedMiners[$0.ipAddress] = MinerRolloutState(miner: $0) }
                        }
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.bottom, 12)
            
            // Miners grid
            ScrollView {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(miners) { miner in
                        MinerSelectionCard(
                            miner: miner,
                            isSelected: model.selectedMiners[miner.ipAddress] != nil
                        ) {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                if model.selectedMiners[miner.ipAddress] != nil {
                                    model.selectedMiners[miner.ipAddress] = nil
                                } else {
                                    model.selectedMiners[miner.ipAddress] = MinerRolloutState(miner: miner)
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}

// MARK: - Profile Summary Card

private struct ProfileSummaryCard: View {
    let profile: MinerProfileTemplate
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        HStack(spacing: 12) {
            // Profile icon
            Image(systemName: "square.stack.3d.up.fill")
                .font(.system(size: 20))
                .foregroundStyle(.blue)
                .frame(width: 40, height: 40)
                .background(Color.blue.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            
            // Profile info
            VStack(alignment: .leading, spacing: 4) {
                Text(profile.name)
                    .font(.system(size: 14, weight: .semibold))
                
                HStack(spacing: 16) {
                    Label(profile.stratumURL, systemImage: "server.rack")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    
                    Label("\(profile.stratumPort)", systemImage: "number")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            // Verified badge
            if profile.fallbackStratumURL != nil {
                Text("Fallback ✓")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.1))
                    .clipShape(Capsule())
            }
        }
        .padding(12)
        .background(colorScheme == .dark ? Color(white: 0.15) : Color(white: 0.97))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

// MARK: - Miner Selection Card

private struct MinerSelectionCard: View {
    let miner: Miner
    let isSelected: Bool
    let onTap: () -> Void
    
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(miner.hostName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    
                    Text(miner.deviceModel ?? miner.ASICModel)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                isSelected
                    ? Color.accentColor.opacity(colorScheme == .dark ? 0.15 : 0.08)
                    : (colorScheme == .dark ? Color(white: 0.12) : Color(white: 0.97))
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor.opacity(0.5) : Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: – Screen 3 · rollout status

private struct RolloutStatusScreen: View {
    @State var model: RolloutWizardModel
    @Environment(\.colorScheme) var colorScheme

    var minerStates: [MinerRolloutState] { Array(model.selectedMiners.values).sorted { $0.miner.hostName < $1.miner.hostName } }
    
    let columns = [
        GridItem(.adaptive(minimum: 180, maximum: 220)),
    ]
    
    private var completedCount: Int {
        model.selectedMiners.values.filter { $0.status == .complete }.count
    }
    
    private var failedCount: Int {
        model.selectedMiners.values.filter { $0.status == .failed }.count
    }
    
    private var progressValue: Float {
        Float(model.selectedMiners.values.filter {
            $0.status == RolloutStatus.complete || $0.status == RolloutStatus.pending(step: 2, total: 2)
        }.count)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Summary header
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Deploying")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(model.selectedProfile?.name ?? "Profile")
                        .font(.system(size: 15, weight: .semibold))
                }
                
                Divider()
                    .frame(height: 30)
                
                HStack(spacing: 16) {
                    StatusBadge(icon: "checkmark.circle.fill", count: completedCount, color: .green, label: "Complete")
                    StatusBadge(icon: "xmark.circle.fill", count: failedCount, color: .red, label: "Failed")
                    StatusBadge(icon: "clock", count: model.selectedMiners.count - completedCount - failedCount, color: .orange, label: "Pending")
                }
                
                Spacer()
            }
            .padding(16)
            .background(colorScheme == .dark ? Color(white: 0.12) : Color(white: 0.97))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.bottom, 16)
            
            // Miners grid
            ScrollView {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(minerStates) { state in
                        MinerRolloutStatusCard(state: state)
                    }
                }
                .padding(.vertical, 4)
            }
            .task {
                model.beginRollout()
            }
            
            // Progress bar
            VStack(spacing: 8) {
                HStack {
                    Text("Overall Progress")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(completedCount)/\(model.selectedMiners.count)")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.primary)
                }
                
                ProgressView(value: progressValue, total: Float(model.selectedMiners.count))
                    .progressViewStyle(LinearProgressViewStyle(tint: .accentColor))
                    .scaleEffect(x: 1, y: 1.5, anchor: .center)
            }
            .padding(.top, 16)
        }
    }
}

// MARK: - Status Badge

private struct StatusBadge: View {
    let icon: String
    let count: Int
    let color: Color
    let label: String
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(color)
            Text("\(count)")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(.primary)
        }
        .help(label)
    }
}

// MARK: - Miner Rollout Status Card

private struct MinerRolloutStatusCard: View {
    let state: MinerRolloutState
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        HStack(spacing: 10) {
            statusIcon
            
            VStack(alignment: .leading, spacing: 2) {
                Text(state.miner.hostName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                
                Text(statusText)
                    .font(.system(size: 10))
                    .foregroundStyle(statusColor)
            }
            
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(colorScheme == .dark ? Color(white: 0.12) : Color(white: 0.97))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(statusColor.opacity(0.3), lineWidth: 1)
        )
    }
    
    @ViewBuilder
    private var statusIcon: some View {
        switch state.status {
        case .pending(let step, let total):
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 2)
                    .frame(width: 20, height: 20)
                Circle()
                    .trim(from: 0, to: CGFloat(step / total))
                    .stroke(Color.orange, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .frame(width: 20, height: 20)
                    .rotationEffect(.degrees(-90))
            }
        case .complete:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(.red)
        }
    }
    
    private var statusText: String {
        switch state.status {
        case .pending(let step, _):
            if step < 0.5 { return "Connecting..." }
            else if step < 1.5 { return "Sending settings..." }
            else { return "Restarting..." }
        case .complete:
            return "Complete"
        case .failed:
            return "Failed"
        }
    }
    
    private var statusColor: Color {
        switch state.status {
        case .pending: return .orange
        case .complete: return .green
        case .failed: return .red
        }
    }
}

// MARK: - Error Types

enum MinerUpdateError: Error {
    case failedRestart(IPAddress, Error)
    case failedUpdate(IPAddress, Error)

    var deviceIpAddress: IPAddress {
        switch self {
        case .failedRestart(let ip, _),
                .failedUpdate(let ip, _):
            return ip
        }
    }
}
