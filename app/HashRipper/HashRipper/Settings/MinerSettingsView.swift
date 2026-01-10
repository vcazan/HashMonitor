//
//  MinerSettingsView.swift
//  HashRipper
//
//  Miner tuning and overclock settings view
//

import SwiftUI
import SwiftData
import AxeOSClient

/// View for adjusting miner overclock and tuning settings
struct MinerSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.minerClientManager) private var minerClientManager
    @Environment(\.modelContext) private var modelContext
    
    let miner: Miner
    
    // Current settings (from latest update)
    @State private var currentFrequency: Int = 0
    @State private var currentVoltage: Int = 0
    @State private var currentFanSpeed: Int = 0
    @State private var currentAutoFan: Bool = true
    
    // Editable settings
    @State private var hostname: String = ""
    @State private var frequency: Int = 500
    @State private var coreVoltage: Int = 1200
    @State private var fanSpeed: Int = 100
    @State private var autoFanSpeed: Bool = true
    @State private var overclockEnabled: Bool = false
    @State private var flipScreen: Bool = false
    @State private var invertScreen: Bool = false
    @State private var invertFanPolarity: Bool = false
    
    // UI State
    @State private var isLoading: Bool = true
    @State private var isSaving: Bool = false
    @State private var showSuccessAlert: Bool = false
    @State private var showErrorAlert: Bool = false
    @State private var errorMessage: String = ""
    @State private var hasChanges: Bool = false
    
    // Miner type specific limits - expanded for overclocking
    private var frequencyRange: ClosedRange<Int> {
        // Universal frequency range for all supported ASICs
        return 495...1000
    }
    
    private var voltageRange: ClosedRange<Int> {
        // Safe voltage range for BM1366/BM1368/BM1370 ASICs
        return 1085...1350
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
            
            Divider()
            
            if isLoading {
                loadingView
            } else {
                ScrollView {
                    VStack(spacing: 20) {
                        // Device Settings
                        deviceSettingsCard
                        
                        // Current Status Card
                        currentStatusCard
                        
                        // Performance Settings
                        performanceSettingsCard
                        
                        // Fan Settings
                        fanSettingsCard
                        
                        // Display Settings
                        displaySettingsCard
                        
                        // Warning for overclock
                        if overclockEnabled {
                            warningCard
                        }
                    }
                    .padding(20)
                }
            }
            
            Divider()
            
            // Footer buttons
            footer
        }
        .frame(width: 480, height: 620)
        .onAppear {
            loadCurrentSettings()
        }
        .alert("Settings Applied", isPresented: $showSuccessAlert) {
            Button("OK") {
                dismiss()
            }
        } message: {
            Text("Your miner settings have been updated. The miner will restart to apply changes.")
        }
        .alert("Error", isPresented: $showErrorAlert) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
    }
    
    // MARK: - Header
    
    private var header: some View {
        HStack(spacing: 12) {
            Image.icon(forMinerType: miner.minerType)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 50, height: 50)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Miner Settings")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text(miner.hostName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Connection status
            HStack(spacing: 4) {
                Circle()
                    .fill(miner.isOffline ? .red : .green)
                    .frame(width: 8, height: 8)
                Text(miner.isOffline ? "Offline" : "Online")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
        }
        .padding(20)
    }
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Loading current settings...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Device Settings Card
    
    private var deviceSettingsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Device", systemImage: "desktopcomputer")
                .font(.headline)
            
            HStack {
                Text("Hostname")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                TextField("Hostname", text: $hostname)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
                    .onChange(of: hostname) { _, _ in hasChanges = true }
            }
            
            Text("The hostname identifies this miner on your network")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    // MARK: - Current Status Card
    
    private var currentStatusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Current Status", systemImage: "gauge.with.dots.needle.bottom.50percent")
                .font(.headline)
            
            HStack(spacing: 16) {
                StatusItem(
                    icon: "speedometer",
                    label: "Frequency",
                    value: "\(currentFrequency) MHz",
                    color: .blue
                )
                
                StatusItem(
                    icon: "bolt.fill",
                    label: "Voltage",
                    value: "\(currentVoltage) mV",
                    color: .orange
                )
                
                StatusItem(
                    icon: "fan.fill",
                    label: "Fan",
                    value: currentAutoFan ? "Auto" : "\(currentFanSpeed)%",
                    color: .cyan
                )
            }
        }
        .padding(16)
        .background(Color.blue.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.blue.opacity(0.2), lineWidth: 1)
        )
    }
    
    // MARK: - Performance Settings Card
    
    private var performanceSettingsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Performance", systemImage: "bolt.circle.fill")
                .font(.headline)
            
            // Overclock Toggle
            Toggle(isOn: $overclockEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Enable Overclock Mode")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("Allows frequency and voltage beyond stock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .onChange(of: overclockEnabled) { _, _ in hasChanges = true }
            
            Divider()
            
            // Frequency Input
            SettingInputRow(
                label: "Frequency",
                value: $frequency,
                unit: "MHz",
                range: frequencyRange,
                step: 5,
                color: .blue,
                onChange: { hasChanges = true }
            )
            
            // Voltage Input
            SettingInputRow(
                label: "Core Voltage",
                value: $coreVoltage,
                unit: "mV",
                range: voltageRange,
                step: 10,
                color: .orange,
                onChange: { hasChanges = true }
            )
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    // MARK: - Fan Settings Card
    
    private var fanSettingsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Fan Control", systemImage: "fan.fill")
                .font(.headline)
            
            Toggle(isOn: $autoFanSpeed) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Automatic Fan Speed")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("Adjusts based on temperature")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .onChange(of: autoFanSpeed) { _, _ in hasChanges = true }
            
            if !autoFanSpeed {
                Divider()
                
                SettingInputRow(
                    label: "Fan Speed",
                    value: $fanSpeed,
                    unit: "%",
                    range: 0...100,
                    step: 5,
                    color: .cyan,
                    onChange: { hasChanges = true }
                )
            }
            
            Toggle(isOn: $invertFanPolarity) {
                Text("Invert Fan Polarity")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .onChange(of: invertFanPolarity) { _, _ in hasChanges = true }
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    // MARK: - Display Settings Card
    
    private var displaySettingsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Display", systemImage: "display")
                .font(.headline)
            
            HStack(spacing: 24) {
                Toggle(isOn: $flipScreen) {
                    Text("Flip Screen")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                .onChange(of: flipScreen) { _, _ in hasChanges = true }
                
                Toggle(isOn: $invertScreen) {
                    Text("Invert Colors")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                .onChange(of: invertScreen) { _, _ in hasChanges = true }
            }
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    // MARK: - Warning Card
    
    private var warningCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundStyle(.orange)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Overclock Warning")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text("May cause instability or hardware damage. Start with small changes and monitor temps.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
    
    // MARK: - Footer
    
    private var footer: some View {
        HStack {
            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            
            Spacer()
            
            if hasChanges {
                Button("Reset") {
                    loadCurrentSettings()
                    hasChanges = false
                }
                .foregroundStyle(.secondary)
            }
            
            Button(action: applySettings) {
                if isSaving {
                    ProgressView()
                        .scaleEffect(0.8)
                        .frame(width: 16, height: 16)
                } else {
                    Text("Apply Settings")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!hasChanges || isSaving || miner.isOffline)
            .keyboardShortcut(.defaultAction)
        }
        .padding(20)
    }
    
    // MARK: - Actions
    
    private func loadCurrentSettings() {
        isLoading = true
        
        Task {
            let macAddress = miner.macAddress
            
            do {
                var descriptor = FetchDescriptor<MinerUpdate>(
                    predicate: #Predicate<MinerUpdate> { update in
                        update.macAddress == macAddress && !update.isFailedUpdate
                    },
                    sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
                )
                descriptor.fetchLimit = 1
                
                let updates = try modelContext.fetch(descriptor)
                
                await MainActor.run {
                    // Load hostname from miner
                    hostname = miner.hostName
                    
                    if let latestUpdate = updates.first {
                        // Use target coreVoltage if available, otherwise estimate from measured voltage
                        if let targetVoltage = latestUpdate.coreVoltage {
                            currentVoltage = targetVoltage
                        } else {
                            // Fallback: measured voltage is in mV * 10
                            let rawVoltage = latestUpdate.voltage ?? 12000
                            currentVoltage = Int(rawVoltage / 10)
                        }
                        
                        currentFrequency = Int(latestUpdate.frequency ?? 500)
                        currentFanSpeed = Int(latestUpdate.fanspeed ?? 100)
                        currentAutoFan = latestUpdate.autofanspeed == 1 || latestUpdate.autofanspeed == nil
                        
                        // Set editable values to current target settings
                        frequency = currentFrequency
                        coreVoltage = currentVoltage
                        fanSpeed = currentFanSpeed
                        autoFanSpeed = currentAutoFan
                        flipScreen = latestUpdate.flipscreen == 1
                        invertScreen = latestUpdate.invertscreen == 1
                        invertFanPolarity = latestUpdate.invertfanpolarity == 1
                    }
                    
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                }
            }
        }
    }
    
    private func applySettings() {
        guard let client = minerClientManager?.client(forIpAddress: miner.ipAddress) else {
            errorMessage = "Could not connect to miner"
            showErrorAlert = true
            return
        }
        
        isSaving = true
        
        Task {
            // Note: coreVoltage is sent as-is (the API expects mV directly)
            let settings = MinerSettings(
                stratumURL: nil,
                fallbackStratumURL: nil,
                stratumUser: nil,
                stratumPassword: nil,
                fallbackStratumUser: nil,
                fallbackStratumPassword: nil,
                stratumPort: nil,
                fallbackStratumPort: nil,
                ssid: nil,
                wifiPass: nil,
                hostname: hostname.isEmpty ? nil : hostname,
                coreVoltage: coreVoltage,
                frequency: frequency,
                flipscreen: flipScreen ? 1 : 0,
                overheatMode: nil,
                overclockEnabled: overclockEnabled ? 1 : 0,
                invertscreen: invertScreen ? 1 : 0,
                invertfanpolarity: invertFanPolarity ? 1 : 0,
                autofanspeed: autoFanSpeed ? 1 : 0,
                fanspeed: autoFanSpeed ? nil : fanSpeed
            )
            
            let result = await client.updateSystemSettings(settings: settings)
            
            await MainActor.run {
                isSaving = false
                
                switch result {
                case .success:
                    // Update the miner's hostname if it changed
                    if !hostname.isEmpty && miner.hostName != hostname {
                        miner.hostName = hostname
                    }
                    showSuccessAlert = true
                case .failure(let error):
                    errorMessage = "Failed to apply settings: \(error)"
                    showErrorAlert = true
                }
            }
        }
    }
}

// MARK: - Setting Input Row (TextField + Stepper)

private struct SettingInputRow: View {
    let label: String
    @Binding var value: Int
    let unit: String
    let range: ClosedRange<Int>
    let step: Int
    let color: Color
    let onChange: () -> Void
    
    @FocusState private var isFocused: Bool
    @State private var textValue: String = ""
    
    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.subheadline)
                .fontWeight(.medium)
                .frame(width: 100, alignment: .leading)
            
            Spacer()
            
            HStack(spacing: 8) {
                // Decrement button
                Button(action: decrement) {
                    Image(systemName: "minus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(value > range.lowerBound ? color : .gray)
                }
                .buttonStyle(.plain)
                .disabled(value <= range.lowerBound)
                
                // Text field
                TextField("", text: $textValue)
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)
                    .frame(width: 70)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .focused($isFocused)
                    .onAppear {
                        textValue = "\(value)"
                    }
                    .onChange(of: value) { _, newValue in
                        if !isFocused {
                            textValue = "\(newValue)"
                        }
                    }
                    .onSubmit {
                        commitTextValue()
                    }
                    .onChange(of: isFocused) { _, focused in
                        if !focused {
                            commitTextValue()
                        }
                    }
                
                // Increment button
                Button(action: increment) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(value < range.upperBound ? color : .gray)
                }
                .buttonStyle(.plain)
                .disabled(value >= range.upperBound)
                
                Text(unit)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: 35, alignment: .leading)
            }
        }
    }
    
    private func increment() {
        let newValue = min(value + step, range.upperBound)
        if newValue != value {
            value = newValue
            textValue = "\(value)"
            onChange()
        }
    }
    
    private func decrement() {
        let newValue = max(value - step, range.lowerBound)
        if newValue != value {
            value = newValue
            textValue = "\(value)"
            onChange()
        }
    }
    
    private func commitTextValue() {
        if let parsed = Int(textValue) {
            let clamped = min(max(parsed, range.lowerBound), range.upperBound)
            if clamped != value {
                value = clamped
                onChange()
            }
            textValue = "\(value)"
        } else {
            textValue = "\(value)"
        }
    }
}

// MARK: - Helper Views

private struct StatusItem: View {
    let icon: String
    let label: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
            
            Text(value)
                .font(.system(.callout, design: .monospaced))
                .fontWeight(.semibold)
            
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    MinerSettingsView(miner: Miner(
        hostName: "bitaxe-001",
        ipAddress: "192.168.1.100",
        ASICModel: "BM1366",
        boardVersion: "402",
        deviceModel: "supra",
        macAddress: "AA:BB:CC:DD:EE:FF"
    ))
}
