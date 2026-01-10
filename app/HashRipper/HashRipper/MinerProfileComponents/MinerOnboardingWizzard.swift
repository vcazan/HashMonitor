//
//  MinerOnboardingWizzard.swift
//  HashRipper
//
//  Created by Matt Sellars
//  Modern iOS 26 / macOS Tahoe style
//

import SwiftUI
import SwiftData
import AxeOSClient

enum ProfileSelection: Hashable {
    case existing(MinerProfileTemplate)
    case new
}

enum WifiSelection: Hashable {
    case existing(MinerWifiConnection)
    case new
}

/// Modern wizard for onboarding a new miner - iOS 26 / macOS Tahoe style
struct NewMinerSetupWizardView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.newMinerScanner) private var deviceRefresher
    @Environment(\.colorScheme) private var colorScheme

    @Query private var connectedClients: [MinerUpdate]
    @Query private var miners: [Miner]
    @Query private var profiles: [MinerProfileTemplate]
    @Query(sort: \MinerWifiConnection.ssid) private var wifiConnections: [MinerWifiConnection]

    // Wizard State
    private let steps = ["Scan", "Name", "Profile", "Wi-Fi", "Review"]
    @State private var currentStep = 0

    // Scan step
    @State private var connectedDevice: DiscoveredDevice? = nil
    @State private var scanInProgress = false
    @State private var showDeviceNotFound = false

    // Name step
    @State private var minerName = ""
    
    // Profile step
    @State private var selectedProfile: MinerProfileTemplate?
    @State private var showingAddProfileSheet = false
    
    // Wi-Fi step
    @State private var selectedWifi: MinerWifiConnection?
    @State private var showingAddWifiSheet = false

    // Finish
    @State private var minerSettings: MinerSettings? = nil
    @State private var showFlashFailedAlert = false

    @State private var wifiSelection: WifiSelection? = nil
    @State private var profileSelection: ProfileSelection? = nil

    var onCancel: () -> Void
    
    private var glassBackground: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(.ultraThinMaterial)
            .shadow(color: .black.opacity(0.1), radius: 20, x: 0, y: 10)
    }

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: colorScheme == .dark 
                    ? [Color(white: 0.08), Color(white: 0.12)]
                    : [Color(white: 0.94), Color(white: 0.98)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
        VStack(spacing: 0) {
                // Modern step indicator
                modernStepIndicator
                    .padding(.horizontal, 40)
                    .padding(.top, 28)
                    .padding(.bottom, 24)
                
                // Content area
                ZStack {
                    switch currentStep {
                    case 0: scanStepView
                    case 1: nameStepView
                    case 2: profileStepView
                    case 3: wifiStepView
                    case 4: reviewStepView
                    default: EmptyView()
                    }
            }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: currentStep)

                // Bottom navigation
                Divider()
                    .padding(.horizontal, 32)

                bottomNavigation
                    .padding(.horizontal, 32)
                    .padding(.vertical, 16)
        }
        }
        .frame(width: 560, height: 600)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .sheet(isPresented: $showingAddProfileSheet) {
            MinerProfileTemplateFormView(
                onSave: { profile in
                    selectedProfile = profile
                    profileSelection = .existing(profile)
                    showingAddProfileSheet = false
                },
                onCancel: {
                    selectedProfile = nil
                    showingAddProfileSheet = false
                }
            )
        }
        .sheet(isPresented: $showingAddWifiSheet) {
            WiFiCredentialsFormView(
                onSave: { wifi in
                    selectedWifi = wifi
                    wifiSelection = .existing(wifi)
                    showingAddWifiSheet = false
                },
                onCancel: {
                    selectedWifi = nil
                    showingAddWifiSheet = false
                }
            )
        }
        .alert("Device Not Found", isPresented: $showDeviceNotFound) {
            Button("OK") { showDeviceNotFound = false }
        } message: {
            Text("No miner detected. Make sure your Mac is connected to the miner's Wi-Fi hotspot (e.g., Bitaxe_XXXX).")
        }
        .alert("Setup Failed", isPresented: $showFlashFailedAlert) {
            Button("OK") { showFlashFailedAlert = false }
        } message: {
            Text("Failed to configure miner settings. Please try again.")
        }
    }

    // MARK: - Modern Step Indicator
    
    private var modernStepIndicator: some View {
        HStack(spacing: 4) {
            ForEach(0..<steps.count, id: \.self) { index in
                Capsule()
                    .fill(index <= currentStep ? Color.blue : Color(nsColor: .separatorColor).opacity(0.5))
                    .frame(height: 4)
                    .animation(.spring(response: 0.3), value: currentStep)
            }
        }
    }
    
    // MARK: - Scan Step
    
    private var scanStepView: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 20)
            
            // Icon with gradient
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.blue, .cyan],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 72, height: 72)

                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(.white)
            }
            
            VStack(spacing: 8) {
                Text("Connect to Miner")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                
                Text("Join your miner's Wi-Fi hotspot, then scan")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            // Device card
            deviceStatusCard
            
            // Scan button
                    if connectedDevice == nil {
                        Button(action: startScan) {
                    HStack(spacing: 10) {
                        if scanInProgress {
                            ProgressView()
                                .scaleEffect(0.8)
                                .tint(.white)
                        } else {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        Text(scanInProgress ? "Scanning..." : "Scan for Miner")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(width: 180, height: 40)
                    .background(
                        Capsule()
                            .fill(scanInProgress ? Color.gray : Color.blue)
                    )
                }
                .buttonStyle(.plain)
            .disabled(scanInProgress)
            }
            
            Spacer(minLength: 20)
        }
        .padding(.horizontal, 40)
    }
    
    private var deviceStatusCard: some View {
        VStack(spacing: 10) {
            if let device = connectedDevice {
                Image.icon(forMinerType: device.info.minerType)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 48, height: 48)
                
                Text(device.info.minerDeviceDisplayName)
                    .font(.system(size: 14, weight: .semibold))
                
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Connected")
                        .foregroundStyle(.green)
                }
                .font(.system(size: 12, weight: .medium))
            } else {
                Image.icon(forMinerType: .Unknown)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 48, height: 48)
                    .opacity(0.4)
                
                Text("Waiting for device...")
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 24)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(colorScheme == .dark ? Color(white: 0.15) : .white)
                .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 3)
        )
    }
    
    // MARK: - Name Step
    
    private var nameStepView: some View {
        VStack(spacing: 28) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.orange, .pink],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)
                
                Image(systemName: "tag.fill")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(.white)
            }
            
            VStack(spacing: 10) {
                Text("Name Your Miner")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                
                Text("Give it a unique name for easy identification")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
            }
            
            // Modern text field
            TextField("", text: $minerName, prompt: Text("e.g., Office Miner").foregroundStyle(.tertiary))
                .font(.system(size: 17))
                .textFieldStyle(.plain)
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(colorScheme == .dark ? Color(white: 0.15) : .white)
                        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
                )
                .frame(maxWidth: 320)
            
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 40)
    }
    
    // MARK: - Profile Step
    
    private var profileStepView: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.purple, .indigo],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 64, height: 64)
                
                Image(systemName: "server.rack")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(.white)
            }
            .padding(.top, 20)
            
            VStack(spacing: 8) {
                Text("Select Pool Profile")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                
                Text("Choose your mining configuration")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            
            // Profile list
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(profiles) { profile in
                        ModernSelectableRow(
                            title: profile.name,
                            subtitle: profile.stratumURL,
                            icon: "server.rack",
                            isSelected: selectedProfile?.id == profile.id
                        ) {
                            withAnimation(.spring(response: 0.3)) {
                                selectedProfile = profile
                                profileSelection = .existing(profile)
                }
            }
                    }
                    
                    // Add new button
                    Button(action: { showingAddProfileSheet = true }) {
                        HStack(spacing: 10) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 18))
                            Text("Create New Profile")
                                .font(.system(size: 14, weight: .medium))
                        }
                        .foregroundStyle(.blue)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 40)
            }
        }
    }
    
    // MARK: - Wi-Fi Step

    private var wifiStepView: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.teal, .green],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 64, height: 64)
                
                Image(systemName: "wifi")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(.white)
            }
            .padding(.top, 20)
            
            VStack(spacing: 8) {
                Text("Select Wi-Fi Network")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                
                Text("Your miner will connect to this network")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(wifiConnections) { wifi in
                        ModernSelectableRow(
                            title: wifi.ssid,
                            subtitle: "Saved network",
                            icon: "wifi",
                            isSelected: selectedWifi?.id == wifi.id
                        ) {
                            withAnimation(.spring(response: 0.3)) {
                                selectedWifi = wifi
                                wifiSelection = .existing(wifi)
                }
            }
                    }
                    
                    Button(action: { showingAddWifiSheet = true }) {
                        HStack(spacing: 10) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 18))
                            Text("Add Wi-Fi Network")
                                .font(.system(size: 14, weight: .medium))
                        }
                        .foregroundStyle(.blue)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 40)
            }
        }
    }

    // MARK: - Review Step
    
    private var reviewStepView: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.green, .mint],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 64, height: 64)
                
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(.white)
            }
            .padding(.top, 20)
            
            VStack(spacing: 8) {
                Text("Ready to Setup")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                
                Text("Review your configuration")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            
            // Summary card
            VStack(spacing: 0) {
                ReviewSummaryRow(icon: "cpu", label: "Device", value: connectedDevice?.info.minerDeviceDisplayName ?? "—")
                Divider().padding(.leading, 44)
                ReviewSummaryRow(icon: "tag", label: "Name", value: minerName.isEmpty ? "—" : minerName)
                Divider().padding(.leading, 44)
                ReviewSummaryRow(icon: "server.rack", label: "Profile", value: selectedProfile?.name ?? "—")
                Divider().padding(.leading, 44)
                ReviewSummaryRow(icon: "wifi", label: "Wi-Fi", value: selectedWifi?.ssid ?? "—")
            }
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(colorScheme == .dark ? Color(white: 0.12) : .white)
                    .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 4)
            )
            .padding(.horizontal, 40)
            
            Spacer()
        }
    }
    
    // MARK: - Bottom Navigation

    private var bottomNavigation: some View {
        HStack {
            Button("Cancel") { onCancel() }
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)

            Spacer()

            HStack(spacing: 12) {
                if currentStep > 0 {
                    Button(action: { withAnimation(.spring(response: 0.35)) { currentStep -= 1 } }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 40, height: 40)
                            .background(
                                Circle()
                                    .fill(colorScheme == .dark ? Color(white: 0.2) : Color(white: 0.92))
                            )
                    }
                    .buttonStyle(.plain)
                }
                
                Button(action: nextAction) {
                    HStack(spacing: 6) {
                        Text(currentStep < steps.count - 1 ? "Next" : "Setup Miner")
                            .font(.system(size: 15, weight: .semibold))
                        if currentStep < steps.count - 1 {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .bold))
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .frame(height: 40)
                    .background(
                        Capsule()
                            .fill(isNextDisabled ? Color.gray : Color.blue)
                    )
                }
                .buttonStyle(.plain)
                    .disabled(isNextDisabled)
            }
        }
    }
    
    // MARK: - Actions

    private var isNextDisabled: Bool {
        switch currentStep {
        case 0: return connectedDevice == nil
        case 1: return minerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case 2: return selectedProfile == nil
        case 3: return selectedWifi == nil
        default: return false
        }
    }
    
    private func nextAction() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            if currentStep < steps.count - 1 {
                currentStep += 1
            } else {
                finishSetup()
            }
        }
    }
    
    private func finishSetup() {
        guard let selectedProfile = selectedProfile,
              let ssid = selectedWifi?.ssid,
              let wifiPassword = try? KeychainHelper.load(account: ssid) else {
            showFlashFailedAlert = true
            return
        }
        
        minerSettings = MinerSettings(
            stratumURL: selectedProfile.stratumURL,
            fallbackStratumURL: selectedProfile.fallbackStratumURL,
            stratumUser: "\(selectedProfile.poolAccount).\(minerName)",
            stratumPassword: selectedProfile.stratumPassword,
            fallbackStratumUser: selectedProfile.fallbackStratumAccount.map { "\($0).\(minerName)" },
            fallbackStratumPassword: selectedProfile.fallbackStratumPassword,
            stratumPort: selectedProfile.stratumPort,
            fallbackStratumPort: selectedProfile.fallbackStratumPort,
            ssid: ssid,
            wifiPass: wifiPassword,
            hostname: minerName,
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
        print("Configuring miner...")
    }
    
    private func startScan() {
        connectedDevice = nil
        scanInProgress = true
        
        Task.detached {
            try? await Task.sleep(for: .seconds(1))
            let result = await deviceRefresher?.scanForNewMiner()
            
            switch result {
            case .some(.success(let newDevice)):
                await MainActor.run {
                    withAnimation(.spring(response: 0.4)) {
                        scanInProgress = false
                        showDeviceNotFound = false
                        connectedDevice = DiscoveredDevice(client: newDevice.client, info: newDevice.clientInfo)
                    }
        }
            case .failure, .none:
                await MainActor.run {
                    scanInProgress = false
                    showDeviceNotFound = true
    }
}
        }
    }
}

// MARK: - Supporting Views

private struct ModernSelectableRow: View {
    let title: String
    let subtitle: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(isSelected ? .white : .secondary)
                    .frame(width: 32, height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(isSelected ? Color.blue : Color(nsColor: .controlBackgroundColor))
                    )
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.blue)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(colorScheme == .dark ? Color(white: 0.12) : .white)
                    .shadow(color: .black.opacity(isSelected ? 0.1 : 0.04), radius: isSelected ? 8 : 4, x: 0, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.blue : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct ReviewSummaryRow: View {
    let icon: String
    let label: String
    let value: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 24)
            
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            
            Spacer()
            
            Text(value)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}
