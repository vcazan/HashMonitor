//
//  MinerSettingsInspector.swift
//  HashRipper
//
//  Miner settings as a native macOS inspector
//

import SwiftUI
import SwiftData
import AxeOSClient

/// Inspector wrapper for miner settings - displayed as a native macOS inspector
struct MinerSettingsInspector: View {
    @Environment(\.minerClientManager) private var minerClientManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    
    let miner: Miner
    @Binding var isPresented: Bool
    
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
    @State private var showRemoveConfirmation: Bool = false
    
    // Miner type specific limits
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
            // Compact header
            inspectorHeader
            
            Divider()
            
            if isLoading {
                loadingView
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Device Settings
                        deviceGroup
                        
                        // Current Status
                        currentStatusGroup
                        
                        // Tuning Mode
                        tuningModeGroup
                        
                        // Cooling
                        coolingGroup
                        
                        // Display
                        displayGroup
                        
                        // Actions
                        actionsGroup
                    }
                    .padding(12)
                }
            }
        }
        .frame(minWidth: 280)
        .background(Color(nsColor: .controlBackgroundColor))
        .onAppear { loadCurrentSettings() }
        .onChange(of: miner.macAddress) { _, _ in
            // Reload settings when user switches to a different miner
            isLoading = true
            hasChanges = false
            loadCurrentSettings()
        }
        .alert("Settings Saved", isPresented: $showSuccessAlert) {
            Button("OK") { }
        } message: {
            Text("Miner settings have been updated successfully.")
        }
        .alert("Remove Miner?", isPresented: $showRemoveConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Remove", role: .destructive) {
                removeMiner()
            }
        } message: {
            Text("Are you sure you want to remove \(miner.hostName) from HashRipper? This will stop monitoring and remove all stored data for this miner.")
        }
        .alert("Error", isPresented: $showErrorAlert) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
    }
    
    // MARK: - Inspector Header
    
    private var inspectorHeader: some View {
        HStack(spacing: 10) {
            Image.icon(forMinerType: miner.minerType)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 28, height: 28)
            
            VStack(alignment: .leading, spacing: 1) {
                Text("Settings")
                    .font(.system(size: 13, weight: .semibold))
                Text(miner.hostName)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            Button(action: { isPresented = false }) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .background(colorScheme == .dark ? Color(white: 0.2) : Color(white: 0.92))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Close")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minHeight: 64)
    }
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.7)
            Text("Loading...")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Device Group
    
    private var deviceGroup: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Hostname")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                
                TextField("Hostname", text: Binding(
                    get: { hostname },
                    set: { hostname = $0; hasChanges = true }
                ))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11))
                .controlSize(.small)
                
                Text("Network identifier for this miner")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
        } label: {
            Text("Device")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
        }
    }
    
    // MARK: - Current Status Group
    
    private var currentStatusGroup: some View {
        GroupBox {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                GridRow {
                    Label("Frequency", systemImage: "cpu")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text("\(currentFrequency) MHz")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                
                GridRow {
                    Label("Core Voltage", systemImage: "bolt")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text("\(currentVoltage) mV")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                
                GridRow {
                    Label("Fan", systemImage: "fan")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(currentAutoFan ? "Auto" : "\(currentFanSpeed)%")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        } label: {
            Text("Current Status")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
        }
    }
    
    // MARK: - Tuning Mode Group
    
    private var tuningModeGroup: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(isOn: Binding(
                    get: { overclockEnabled },
                    set: { newValue in
                        overclockEnabled = newValue
                        hasChanges = true
                        UserDefaults.standard.set(newValue, forKey: "overclockEnabled_\(miner.macAddress)")
                    }
                )) {
                    HStack(spacing: 6) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(overclockEnabled ? .yellow : .gray)
                        Text("Enable Tuning")
                            .font(.system(size: 11))
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                
                if overclockEnabled {
                    Divider()
                    
                    // Frequency
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Frequency")
                                .font(.system(size: 11))
                            Spacer()
                            Text("\(frequency) MHz")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(.blue)
                        }
                        
                        HStack(spacing: 4) {
                            Stepper("", value: $frequency, in: frequencyRange, step: 25) { _ in
                                hasChanges = true
                            }
                            .labelsHidden()
                            
                            Slider(value: Binding(
                                get: { Double(frequency) },
                                set: { frequency = Int($0); hasChanges = true }
                            ), in: Double(frequencyRange.lowerBound)...Double(frequencyRange.upperBound), step: 25)
                            .controlSize(.small)
                        }
                    }
                    
                    // Core Voltage
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Core Voltage")
                                .font(.system(size: 11))
                            Spacer()
                            Text("\(coreVoltage) mV")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(.orange)
                        }
                        
                        HStack(spacing: 4) {
                            Stepper("", value: $coreVoltage, in: voltageRange, step: 10) { _ in
                                hasChanges = true
                            }
                            .labelsHidden()
                            
                            Slider(value: Binding(
                                get: { Double(coreVoltage) },
                                set: { coreVoltage = Int($0); hasChanges = true }
                            ), in: Double(voltageRange.lowerBound)...Double(voltageRange.upperBound), step: 10)
                            .controlSize(.small)
                        }
                    }
                    
                    // Warning
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.orange)
                        Text("Use at your own risk")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 2)
                }
            }
        } label: {
            Text("Performance")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
        }
    }
    
    // MARK: - Cooling Group
    
    private var coolingGroup: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: Binding(
                    get: { autoFanSpeed },
                    set: { autoFanSpeed = $0; hasChanges = true }
                )) {
                    Text("Auto Fan Speed")
                        .font(.system(size: 11))
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                
                if !autoFanSpeed {
                    HStack {
                        Text("Speed")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Slider(value: Binding(
                            get: { Double(fanSpeed) },
                            set: { fanSpeed = Int($0); hasChanges = true }
                        ), in: 0...100, step: 5)
                        .controlSize(.small)
                        Text("\(fanSpeed)%")
                            .font(.system(size: 10, design: .monospaced))
                            .frame(width: 32, alignment: .trailing)
                    }
                }
                
                Toggle(isOn: Binding(
                    get: { invertFanPolarity },
                    set: { invertFanPolarity = $0; hasChanges = true }
                )) {
                    Text("Invert Fan Polarity")
                        .font(.system(size: 11))
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
            }
        } label: {
            Text("Cooling")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
        }
    }
    
    // MARK: - Display Group
    
    private var displayGroup: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: Binding(
                    get: { flipScreen },
                    set: { flipScreen = $0; hasChanges = true }
                )) {
                    Text("Flip Screen")
                        .font(.system(size: 11))
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                
                Toggle(isOn: Binding(
                    get: { invertScreen },
                    set: { invertScreen = $0; hasChanges = true }
                )) {
                    Text("Invert Colors")
                        .font(.system(size: 11))
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
            }
        } label: {
            Text("Display")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
        }
    }
    
    // MARK: - Actions Group
    
    private var actionsGroup: some View {
        VStack(spacing: 8) {
            // Save button - native macOS style
            Button(action: saveSettings) {
                HStack(spacing: 4) {
                    if isSaving {
                        ProgressView()
                            .scaleEffect(0.5)
                            .frame(width: 12, height: 12)
                    }
                    Text(isSaving ? "Saving…" : "Apply Changes")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .disabled(!hasChanges || isSaving)
            
            Divider()
                .padding(.vertical, 4)
            
            // Remove miner - subtle destructive action
            Button(role: .destructive, action: { showRemoveConfirmation = true }) {
                Label("Remove Miner…", systemImage: "trash")
                    .font(.system(size: 11))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.red.opacity(0.8))
        }
    }
    
    // MARK: - Actions
    
    private func loadCurrentSettings() {
        Task {
            // Get the latest update for this miner
            let macAddress = miner.macAddress
            let descriptor = FetchDescriptor<MinerUpdate>(
                predicate: #Predicate<MinerUpdate> { $0.macAddress == macAddress },
                sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
            )
            
            do {
                let updates = try modelContext.fetch(descriptor)
                if let latestUpdate = updates.first {
                    await MainActor.run {
                        currentFrequency = Int(latestUpdate.frequency ?? 500)
                        currentVoltage = latestUpdate.coreVoltage ?? 1200
                        currentFanSpeed = Int(latestUpdate.fanspeed ?? 100)
                        currentAutoFan = (latestUpdate.autofanspeed ?? 1) == 1
                        
                        // Set editable values to current
                        hostname = miner.hostName
                        frequency = Int(latestUpdate.frequency ?? 500)
                        coreVoltage = latestUpdate.coreVoltage ?? 1200
                        fanSpeed = Int(latestUpdate.fanspeed ?? 100)
                        autoFanSpeed = (latestUpdate.autofanspeed ?? 1) == 1
                        flipScreen = (latestUpdate.flipscreen ?? 0) == 1
                        invertScreen = (latestUpdate.invertscreen ?? 0) == 1
                        invertFanPolarity = (latestUpdate.invertfanpolarity ?? 0) == 1
                        // Load overclock state from UserDefaults (persisted per-miner)
                        overclockEnabled = UserDefaults.standard.bool(forKey: "overclockEnabled_\(miner.macAddress)")
                        
                        isLoading = false
                    }
                } else {
                    await MainActor.run {
                        hostname = miner.hostName
                        isLoading = false
                    }
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = "Failed to load settings"
                    showErrorAlert = true
                }
            }
        }
    }
    
    private func saveSettings() {
        guard let client = minerClientManager?.client(forIpAddress: miner.ipAddress) else {
            errorMessage = "Could not connect to miner"
            showErrorAlert = true
            return
        }
        
        isSaving = true
        
        Task {
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
                    hasChanges = false
                    
                    // Update the miner's hostname if it changed
                    if !hostname.isEmpty && miner.hostName != hostname {
                        miner.hostName = hostname
                    }
                    
                    showSuccessAlert = true
                    
                    // Update current values
                    currentFrequency = frequency
                    currentVoltage = coreVoltage
                    currentFanSpeed = fanSpeed
                    currentAutoFan = autoFanSpeed
                    
                case .failure(let error):
                    errorMessage = "Failed to save settings: \(error)"
                    showErrorAlert = true
                }
            }
        }
    }
    
    private func removeMiner() {
        // Remove the miner from the client manager first
        minerClientManager?.removeMiner(ipAddress: miner.ipAddress)
        
        // Delete the miner from the database
        modelContext.delete(miner)
        
        // Also delete associated MinerUpdate records
        let macAddress = miner.macAddress
        let updateDescriptor = FetchDescriptor<MinerUpdate>(
            predicate: #Predicate<MinerUpdate> { $0.macAddress == macAddress }
        )
        
        do {
            let updates = try modelContext.fetch(updateDescriptor)
            for update in updates {
                modelContext.delete(update)
            }
            try modelContext.save()
        } catch {
            // Log error but continue - miner is already removed
            print("Error cleaning up miner updates: \(error)")
        }
        
        // Close the inspector
        isPresented = false
        
        // Post notification to refresh the miner list
        NotificationCenter.default.post(name: .minerRemoved, object: nil)
    }
}

// Notification for miner removal
extension Notification.Name {
    static let minerRemoved = Notification.Name("minerRemoved")
}
