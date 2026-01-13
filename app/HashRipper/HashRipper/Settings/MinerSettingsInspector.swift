//
//  MinerSettingsInspector.swift
//  HashRipper
//
//  Miner settings as a native macOS inspector
//

import SwiftUI
import SwiftData
import AxeOSClient
import AvalonClient

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
    
    // Pool settings
    @State private var stratumURL: String = ""
    @State private var stratumPort: String = ""
    @State private var stratumUser: String = ""
    @State private var stratumPassword: String = ""
    
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
            } else if miner.isAvalonMiner {
                // Avalon miners - limited API access
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        avalonDeviceGroup
                        avalonStatusGroup
                        avalonFanGroup
                        avalonPerformanceGroup
                        avalonActionsGroup
                    }
                    .padding(12)
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Device Settings
                        deviceGroup
                        
                        // Pool Settings
                        poolGroup
                        
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
    
    // MARK: - Pool Group
    
    private var poolGroup: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                // Pool URL
                HStack {
                    Text("Pool URL")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(width: 60, alignment: .leading)
                    TextField("stratum+tcp://pool.example.com", text: Binding(
                        get: { stratumURL },
                        set: { stratumURL = $0; hasChanges = true }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
                    .controlSize(.small)
                }
                
                // Port
                HStack {
                    Text("Port")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(width: 60, alignment: .leading)
                    TextField("3333", text: Binding(
                        get: { stratumPort },
                        set: { stratumPort = $0; hasChanges = true }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
                    .controlSize(.small)
                    .frame(width: 70)
                    Spacer()
                }
                
                // Worker
                HStack {
                    Text("Worker")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(width: 60, alignment: .leading)
                    TextField("bc1q...address.worker", text: Binding(
                        get: { stratumUser },
                        set: { stratumUser = $0; hasChanges = true }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
                    .controlSize(.small)
                }
                
                // Password
                HStack {
                    Text("Password")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(width: 60, alignment: .leading)
                    SecureField("Optional", text: Binding(
                        get: { stratumPassword },
                        set: { stratumPassword = $0; hasChanges = true }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
                    .controlSize(.small)
                }
                
                Text("Stratum pool configuration")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
        } label: {
            Text("Mining Pool")
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
                            Stepper("", value: $frequency, in: frequencyRange, step: 5) { _ in
                                hasChanges = true
                            }
                            .labelsHidden()
                            
                            Slider(value: Binding(
                                get: { Double(frequency) },
                                set: { frequency = Int($0); hasChanges = true }
                            ), in: Double(frequencyRange.lowerBound)...Double(frequencyRange.upperBound), step: 5)
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
    
    // MARK: - Avalon Device Group
    
    private var avalonDeviceGroup: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Hostname")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(miner.hostName)
                        .font(.system(size: 11))
                }
                
                HStack {
                    Text("Model")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(miner.minerDeviceDisplayName)
                        .font(.system(size: 11))
                }
                
                HStack {
                    Text("IP Address")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(miner.ipAddress)
                        .font(.system(size: 11, design: .monospaced))
                }
                
                Text("Avalon miners use CGMiner API with limited configuration")
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
    
    // MARK: - Avalon Status Group
    
    private var avalonStatusGroup: some View {
        GroupBox {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                GridRow {
                    Label("Pool", systemImage: "network")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(stratumURL.isEmpty ? "—" : stratumURL)
                        .font(.system(size: 11))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                
                GridRow {
                    Label("Worker", systemImage: "person")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(stratumUser.isEmpty ? "—" : stratumUser)
                        .font(.system(size: 11))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                
                GridRow {
                    Label("Frequency", systemImage: "cpu")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text("\(currentFrequency) MHz")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                
                GridRow {
                    Label("Fan", systemImage: "fan")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text("\(currentFanSpeed)%")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        } label: {
            Text("Mining Status")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
        }
    }
    
    // MARK: - Avalon Fan Group
    
    @State private var avalonFanSpeed: Int = 100
    
    private var avalonFanGroup: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Fan Speed")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Slider(value: Binding(
                        get: { Double(avalonFanSpeed) },
                        set: { avalonFanSpeed = Int($0) }
                    ), in: 0...100, step: 5)
                    .controlSize(.small)
                    Text("\(avalonFanSpeed)%")
                        .font(.system(size: 10, design: .monospaced))
                        .frame(width: 32, alignment: .trailing)
                }
            }
        } label: {
            Text("Fan Control")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
        }
        .onAppear {
            avalonFanSpeed = currentFanSpeed
        }
    }
    
    // MARK: - Avalon Performance Group
    
    @State private var avalonPerformanceMode: String = "normal"
    
    private var avalonPerformanceGroup: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Mode", selection: $avalonPerformanceMode) {
                    Text("Low").tag("low")
                    Text("Normal").tag("normal")
                    Text("High").tag("high")
                }
                .pickerStyle(.segmented)
                .controlSize(.small)
                
                Text("Higher modes increase hash rate but also power and heat")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
        } label: {
            Text("Performance")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
        }
    }
    
    // MARK: - Avalon Actions Group
    
    @State private var isApplyingAvalonSettings: Bool = false
    
    private var avalonActionsGroup: some View {
        VStack(spacing: 8) {
            // Apply Settings button
            Button(action: applyAvalonSettings) {
                HStack(spacing: 4) {
                    if isApplyingAvalonSettings {
                        ProgressView()
                            .scaleEffect(0.5)
                            .frame(width: 12, height: 12)
                    }
                    Text(isApplyingAvalonSettings ? "Applying…" : "Apply Settings")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .disabled(isApplyingAvalonSettings)
            
            HStack(spacing: 8) {
                // Restart button
                Button(action: restartAvalonMiner) {
                    Label("Restart", systemImage: "arrow.clockwise")
                        .font(.system(size: 11))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                // Web UI button
                Button(action: openAvalonWebUI) {
                    Label("Web UI", systemImage: "safari")
                        .font(.system(size: 11))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            
            Divider()
                .padding(.vertical, 4)
            
            // Remove miner
            Button(role: .destructive, action: { showRemoveConfirmation = true }) {
                Label("Remove Miner…", systemImage: "trash")
                    .font(.system(size: 11))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.red.opacity(0.8))
            
            Text("Pool settings can be changed via the web interface")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
    }
    
    private func applyAvalonSettings() {
        isApplyingAvalonSettings = true
        
        Task {
            let client = AvalonClient(deviceIpAddress: miner.ipAddress, timeout: 5.0)
            
            // Apply fan speed
            let _ = await client.setFanSpeed(percent: avalonFanSpeed)
            
            // Apply performance mode
            let _ = await client.setPerformanceMode(mode: avalonPerformanceMode)
            
            await MainActor.run {
                isApplyingAvalonSettings = false
                showSuccessAlert = true
            }
        }
    }
    
    private func restartAvalonMiner() {
        Task {
            let client = AvalonClient(deviceIpAddress: miner.ipAddress, timeout: 5.0)
            let _ = await client.restart()
        }
    }
    
    private func openAvalonWebUI() {
        if let url = URL(string: "http://\(miner.ipAddress)") {
            NSWorkspace.shared.open(url)
        }
    }
    
    // MARK: - Actions Group
    
    private var actionsGroup: some View {
        VStack(spacing: 8) {
            // Save and Revert buttons
            HStack(spacing: 8) {
                // Revert button
                Button(action: {
                    loadCurrentSettings()
                    hasChanges = false
                }) {
                    Text("Revert")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .disabled(!hasChanges || isSaving)
                
                // Save button
                Button(action: saveSettings) {
                    HStack(spacing: 4) {
                        if isSaving {
                            ProgressView()
                                .scaleEffect(0.5)
                                .frame(width: 12, height: 12)
                        }
                        Text(isSaving ? "Saving…" : "Apply")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(!hasChanges || isSaving)
            }
            
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
                        
                        // Load pool settings
                        stratumURL = latestUpdate.stratumURL
                        stratumPort = latestUpdate.stratumPort > 0 ? String(latestUpdate.stratumPort) : ""
                        stratumUser = latestUpdate.stratumUser
                        stratumPassword = "" // Password is not stored for security
                        
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
        // Settings updates only work for AxeOS miners
        guard let client = minerClientManager?.axeOSClient(forIpAddress: miner.ipAddress) else {
            errorMessage = miner.isAvalonMiner ? "Settings updates not supported for Avalon miners" : "Could not connect to miner"
            showErrorAlert = true
            return
        }
        
        isSaving = true
        
        Task {
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
