//
//  MinerSettingsSheet.swift
//  HashRipper-iOS
//
//  Professional miner settings with muted, sophisticated design
//

import SwiftUI
import SwiftData
import HashRipperKit
import AxeOSClient

struct MinerSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    let miner: Miner
    
    // Current values (read-only display)
    @State private var currentFrequency: Int = 0
    @State private var currentVoltage: Int = 0
    @State private var currentFanSpeed: Int = 0
    @State private var currentAutoFan: Bool = true
    
    // Editable settings
    @State private var frequency: Int = 500
    @State private var coreVoltage: Int = 1200
    @State private var fanSpeed: Int = 100
    @State private var autoFanSpeed: Bool = true
    @State private var tuningEnabled: Bool = false
    @State private var flipScreen: Bool = false
    @State private var invertScreen: Bool = false
    @State private var invertFanPolarity: Bool = false
    
    // Device settings
    @State private var hostname: String = ""
    
    // Pool settings
    @State private var stratumURL: String = ""
    @State private var stratumPort: String = ""
    @State private var stratumUser: String = ""
    @State private var stratumPassword: String = ""
    
    // UI State
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var showSuccessAlert = false
    @State private var showErrorAlert = false
    @State private var showRemoveAlert = false
    @State private var errorMessage: String = ""
    @State private var hasChanges = false
    
    private var frequencyRange: ClosedRange<Int> { 495...1000 }
    private var voltageRange: ClosedRange<Int> { 1085...1350 }
    
    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    loadingView
                } else {
                    settingsContent
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                
                ToolbarItem(placement: .principal) {
                    if hasChanges && !isLoading {
                        Button("Revert") {
                            Task { await loadCurrentSettings() }
                            hasChanges = false
                        }
                        .font(.system(size: 14))
                        .foregroundStyle(AppColors.subtleText)
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save") {
                            Task { await saveSettings() }
                        }
                        .fontWeight(.semibold)
                        .foregroundStyle(hasChanges ? AppColors.accent : AppColors.mutedText)
                        .disabled(!hasChanges)
                    }
                }
            }
            .alert("Settings Saved", isPresented: $showSuccessAlert) {
                Button("OK") { dismiss() }
            } message: {
                Text("Miner settings updated successfully.")
            }
            .alert("Error", isPresented: $showErrorAlert) {
                Button("OK") { }
            } message: {
                Text(errorMessage)
            }
            .alert("Remove Miner?", isPresented: $showRemoveAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Remove", role: .destructive) { removeMiner() }
            } message: {
                Text("Remove \(miner.hostName) and all stored data?")
            }
        }
        .task {
            await loadCurrentSettings()
        }
    }
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(AppColors.accent)
            Text("Loading settings...")
                .font(.system(size: 14))
                .foregroundStyle(AppColors.subtleText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Settings Content
    
    private var settingsContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                deviceCard
                poolCard
                statusCard
                performanceCard
                coolingCard
                displayCard
                dangerCard
            }
            .padding(16)
        }
    }
    
    // MARK: - Device Card
    
    private var deviceCard: some View {
        SettingsCard(title: "Device", icon: "desktopcomputer") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Hostname")
                    .font(.system(size: 12))
                    .foregroundStyle(AppColors.subtleText)
                
                TextField("Hostname", text: Binding(
                    get: { hostname },
                    set: { hostname = $0; hasChanges = true }
                ))
                .font(.system(size: 15, weight: .medium, design: .monospaced))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .padding(12)
                .background(Color(.tertiarySystemFill))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }
    
    // MARK: - Pool Card
    
    private var poolCard: some View {
        SettingsCard(title: "Mining Pool", icon: "server.rack") {
            VStack(spacing: 12) {
                SettingsTextField(label: "Pool URL", text: Binding(
                    get: { stratumURL },
                    set: { stratumURL = $0; hasChanges = true }
                ), placeholder: "stratum+tcp://pool.example.com")
                .textContentType(.URL)
                
                SettingsTextField(label: "Port", text: Binding(
                    get: { stratumPort },
                    set: { stratumPort = $0; hasChanges = true }
                ), placeholder: "3333")
                .keyboardType(.numberPad)
                
                SettingsTextField(label: "Worker", text: Binding(
                    get: { stratumUser },
                    set: { stratumUser = $0; hasChanges = true }
                ), placeholder: "wallet.worker")
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Password")
                        .font(.system(size: 12))
                        .foregroundStyle(AppColors.subtleText)
                    
                    SecureField("Optional", text: Binding(
                        get: { stratumPassword },
                        set: { stratumPassword = $0; hasChanges = true }
                    ))
                    .font(.system(size: 15))
                    .padding(12)
                    .background(Color(.tertiarySystemFill))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }
    
    // MARK: - Status Card
    
    private var statusCard: some View {
        SettingsCard(title: "Current Status", icon: "info.circle") {
            VStack(spacing: 0) {
                StatusRow(label: "Frequency", value: "\(currentFrequency) MHz")
                Divider().padding(.leading, 16)
                StatusRow(label: "Core Voltage", value: "\(currentVoltage) mV")
                Divider().padding(.leading, 16)
                StatusRow(label: "Fan", value: currentAutoFan ? "Auto" : "\(currentFanSpeed)%")
            }
        }
    }
    
    // MARK: - Performance Card
    
    private var performanceCard: some View {
        SettingsCard(title: "Performance", icon: "bolt.fill") {
            VStack(spacing: 16) {
                Toggle(isOn: Binding(
                    get: { tuningEnabled },
                    set: { tuningEnabled = $0; hasChanges = true }
                )) {
                    HStack(spacing: 10) {
                        Image(systemName: "bolt.fill")
                            .foregroundStyle(tuningEnabled ? AppColors.warning : AppColors.mutedText)
                            .font(.system(size: 14))
                        Text("Enable Tuning")
                            .font(.system(size: 15))
                    }
                }
                .tint(AppColors.accent)
                
                if tuningEnabled {
                    Divider()
                    
                    // Frequency Slider
                    SliderControl(
                        label: "Frequency",
                        value: $frequency,
                        range: frequencyRange,
                        step: 5,
                        unit: "MHz",
                        color: AppColors.frequency,
                        onChange: { hasChanges = true }
                    )
                    
                    // Voltage Slider
                    SliderControl(
                        label: "Core Voltage",
                        value: $coreVoltage,
                        range: voltageRange,
                        step: 10,
                        unit: "mV",
                        color: AppColors.warning,
                        onChange: { hasChanges = true }
                    )
                    
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(AppColors.warning)
                        Text("Modifying these settings may affect stability")
                            .font(.system(size: 11))
                            .foregroundStyle(AppColors.warning)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppColors.warningLight)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }
    
    // MARK: - Cooling Card
    
    private var coolingCard: some View {
        SettingsCard(title: "Cooling", icon: "fan.fill") {
            VStack(spacing: 16) {
                Toggle(isOn: Binding(
                    get: { autoFanSpeed },
                    set: { autoFanSpeed = $0; hasChanges = true }
                )) {
                    Text("Auto Fan Speed")
                        .font(.system(size: 15))
                }
                .tint(AppColors.accent)
                
                if !autoFanSpeed {
                    Divider()
                    
                    SliderControl(
                        label: "Fan Speed",
                        value: $fanSpeed,
                        range: 0...100,
                        step: 5,
                        unit: "%",
                        color: AppColors.fan,
                        onChange: { hasChanges = true }
                    )
                }
                
                Divider()
                
                Toggle(isOn: Binding(
                    get: { invertFanPolarity },
                    set: { invertFanPolarity = $0; hasChanges = true }
                )) {
                    Text("Invert Fan Polarity")
                        .font(.system(size: 15))
                }
                .tint(AppColors.accent)
            }
        }
    }
    
    // MARK: - Display Card
    
    private var displayCard: some View {
        SettingsCard(title: "Display", icon: "display") {
            VStack(spacing: 12) {
                Toggle(isOn: Binding(
                    get: { flipScreen },
                    set: { flipScreen = $0; hasChanges = true }
                )) {
                    Text("Flip Screen")
                        .font(.system(size: 15))
                }
                .tint(AppColors.accent)
                
                Divider()
                
                Toggle(isOn: Binding(
                    get: { invertScreen },
                    set: { invertScreen = $0; hasChanges = true }
                )) {
                    Text("Invert Colors")
                        .font(.system(size: 15))
                }
                .tint(AppColors.accent)
            }
        }
    }
    
    // MARK: - Danger Card
    
    private var dangerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Danger Zone")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppColors.error)
            
            Button {
                showRemoveAlert = true
            } label: {
                HStack {
                    Spacer()
                    Image(systemName: "trash")
                    Text("Remove Miner")
                    Spacer()
                }
                .font(.system(size: 15, weight: .medium))
            }
            .foregroundStyle(AppColors.error)
            .padding(14)
            .background(AppColors.errorLight)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            
            Text("Removes all monitoring and stored data")
                .font(.system(size: 11))
                .foregroundStyle(AppColors.mutedText)
        }
        .padding(14)
        .cardStyle()
    }
    
    // MARK: - Actions
    
    private func loadCurrentSettings() async {
        isLoading = true
        defer { isLoading = false }
        
        let client = AxeOSClient(deviceIpAddress: miner.ipAddress, urlSession: .shared)
        let result = await client.getSystemInfo()
        
        if case .success(let info) = result {
            await MainActor.run {
                currentFrequency = Int(info.frequency ?? 500)
                currentVoltage = info.coreVoltage ?? 1200
                currentFanSpeed = Int(info.fanspeed ?? 100)
                currentAutoFan = (info.autofanspeed ?? 1) == 1
                
                frequency = Int(info.frequency ?? 500)
                coreVoltage = info.coreVoltage ?? 1200
                fanSpeed = Int(info.fanspeed ?? 100)
                autoFanSpeed = (info.autofanspeed ?? 1) == 1
                flipScreen = (info.flipscreen ?? 0) == 1
                invertScreen = (info.invertscreen ?? 0) == 1
                invertFanPolarity = (info.invertfanpolarity ?? 0) == 1
                
                hostname = info.hostname
                stratumURL = info.stratumURL ?? ""
                stratumPort = String(info.stratumPort ?? 0)
                stratumUser = info.stratumUser ?? ""
                
                tuningEnabled = UserDefaults.standard.bool(forKey: "tuningEnabled_\(miner.macAddress)")
            }
        }
    }
    
    private func saveSettings() async {
        isSaving = true
        defer { isSaving = false }
        
        UserDefaults.standard.set(tuningEnabled, forKey: "tuningEnabled_\(miner.macAddress)")
        
        let client = AxeOSClient(deviceIpAddress: miner.ipAddress, urlSession: .shared)
        
        let settings = MinerSettings(
            stratumURL: stratumURL.isEmpty ? nil : stratumURL,
            fallbackStratumURL: nil,
            stratumUser: stratumUser.isEmpty ? nil : stratumUser,
            stratumPassword: stratumPassword.isEmpty ? nil : stratumPassword,
            fallbackStratumUser: nil,
            fallbackStratumPassword: nil,
            stratumPort: Int(stratumPort),
            fallbackStratumPort: nil,
            ssid: nil,
            wifiPass: nil,
            hostname: hostname.isEmpty ? nil : hostname,
            coreVoltage: tuningEnabled ? coreVoltage : nil,
            frequency: tuningEnabled ? frequency : nil,
            flipscreen: flipScreen ? 1 : 0,
            overheatMode: nil,
            overclockEnabled: tuningEnabled ? 1 : 0,
            invertscreen: invertScreen ? 1 : 0,
            invertfanpolarity: invertFanPolarity ? 1 : 0,
            autofanspeed: autoFanSpeed ? 1 : 0,
            fanspeed: autoFanSpeed ? nil : fanSpeed
        )
        
        let result = await client.updateSystemSettings(settings: settings)
        
        await MainActor.run {
            switch result {
            case .success:
                hasChanges = false
                currentFrequency = frequency
                currentVoltage = coreVoltage
                currentFanSpeed = fanSpeed
                currentAutoFan = autoFanSpeed
                
                if !hostname.isEmpty && miner.hostName != hostname {
                    miner.hostName = hostname
                }
                showSuccessAlert = true
                
            case .failure(let error):
                errorMessage = "Failed to save: \(error.localizedDescription)"
                showErrorAlert = true
            }
        }
    }
    
    private func removeMiner() {
        let macAddress = miner.macAddress
        let updateDescriptor = FetchDescriptor<MinerUpdate>(
            predicate: #Predicate<MinerUpdate> { $0.macAddress == macAddress }
        )
        
        do {
            let updates = try modelContext.fetch(updateDescriptor)
            for update in updates { modelContext.delete(update) }
        } catch {
            print("Error cleaning up miner updates: \(error)")
        }
        
        modelContext.delete(miner)
        
        do {
            try modelContext.save()
        } catch {
            print("Error saving after miner deletion: \(error)")
        }
        
        dismiss()
    }
}

// MARK: - Supporting Views

struct SettingsCard<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.subtleText)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColors.subtleText)
            }
            
            content
        }
        .padding(14)
        .cardStyle()
    }
}

struct SettingsTextField: View {
    let label: String
    @Binding var text: String
    let placeholder: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(AppColors.subtleText)
            
            TextField(placeholder, text: $text)
                .font(.system(size: 15))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .padding(12)
                .background(Color(.tertiarySystemFill))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

struct StatusRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 14))
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundStyle(AppColors.subtleText)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 4)
    }
}

struct SliderControl: View {
    let label: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int
    let unit: String
    let color: Color
    let onChange: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(label)
                    .font(.system(size: 14))
                Spacer()
                Text("\(value) \(unit)")
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(color)
            }
            
            HStack(spacing: 12) {
                Button {
                    if value > range.lowerBound {
                        value -= step
                        onChange()
                    }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(value > range.lowerBound ? color : AppColors.mutedText)
                }
                .buttonStyle(.plain)
                
                Slider(
                    value: Binding(
                        get: { Double(value) },
                        set: { value = Int($0); onChange() }
                    ),
                    in: Double(range.lowerBound)...Double(range.upperBound),
                    step: Double(step)
                )
                .tint(color)
                
                Button {
                    if value < range.upperBound {
                        value += step
                        onChange()
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(value < range.upperBound ? color : AppColors.mutedText)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

#Preview {
    MinerSettingsSheet(miner: Miner(
        hostName: "test-miner",
        ipAddress: "192.168.1.100",
        ASICModel: "BM1366",
        macAddress: "AA:BB:CC:DD:EE:FF"
    ))
}
