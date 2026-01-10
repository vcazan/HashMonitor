//
//  MinerSettingsSheet.swift
//  HashRipper-iOS
//
//  Complete miner tuning settings matching macOS functionality
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
    
    // Miner type specific limits
    private var frequencyRange: ClosedRange<Int> {
        switch miner.minerType {
        case .BitaxeGamma, .BitaxeGammaTurbo:
            return 400...800
        case .BitaxeSupra:
            return 400...800
        case .BitaxeUltra:
            return 400...750
        case .NerdQAxePlus, .NerdQAxePlusPlus:
            return 400...800
        case .NerdOCTAXE:
            return 400...800
        case .NerdQX:
            return 400...800
        default:
            return 400...800
        }
    }
    
    private var voltageRange: ClosedRange<Int> {
        return 1000...1500
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    loadingView
                } else {
                    settingsForm
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
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
                        .disabled(!hasChanges)
                    }
                }
            }
            .alert("Settings Saved", isPresented: $showSuccessAlert) {
                Button("OK") { dismiss() }
            } message: {
                Text("Miner settings have been updated successfully.")
            }
            .alert("Error", isPresented: $showErrorAlert) {
                Button("OK") { }
            } message: {
                Text(errorMessage)
            }
            .alert("Remove Miner?", isPresented: $showRemoveAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Remove", role: .destructive) {
                    removeMiner()
                }
            } message: {
                Text("Are you sure you want to remove \(miner.hostName)? This will remove all stored data for this miner.")
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
            Text("Loading settings...")
                .foregroundStyle(.secondary)
        }
    }
    
    // MARK: - Settings Form
    
    private var settingsForm: some View {
        Form {
            // Pool Configuration Section
            poolSection
            
            // Current Status Section
            currentStatusSection
            
            // Performance Tuning Section
            performanceSection
            
            // Cooling Section
            coolingSection
            
            // Display Section
            displaySection
            
            // Danger Zone
            dangerZoneSection
        }
    }
    
    // MARK: - Pool Section
    
    private var poolSection: some View {
        Section {
            TextField("Pool URL", text: Binding(
                get: { stratumURL },
                set: { stratumURL = $0; hasChanges = true }
            ))
            .textContentType(.URL)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            
            TextField("Port", text: Binding(
                get: { stratumPort },
                set: { stratumPort = $0; hasChanges = true }
            ))
            .keyboardType(.numberPad)
            
            TextField("Worker/Username", text: Binding(
                get: { stratumUser },
                set: { stratumUser = $0; hasChanges = true }
            ))
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            
            SecureField("Password (optional)", text: Binding(
                get: { stratumPassword },
                set: { stratumPassword = $0; hasChanges = true }
            ))
        } header: {
            Label("Mining Pool", systemImage: "server.rack")
        } footer: {
            Text("Configure the stratum pool your miner connects to")
        }
    }
    
    // MARK: - Current Status Section
    
    private var currentStatusSection: some View {
        Section {
            LabeledContent("Frequency") {
                Text("\(currentFrequency) MHz")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            
            LabeledContent("Core Voltage") {
                Text("\(currentVoltage) mV")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            
            LabeledContent("Fan") {
                Text(currentAutoFan ? "Auto" : "\(currentFanSpeed)%")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Current Status")
        } footer: {
            Text("Current miner configuration values")
        }
    }
    
    // MARK: - Performance Section
    
    private var performanceSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { tuningEnabled },
                set: { tuningEnabled = $0; hasChanges = true }
            )) {
                HStack {
                    Image(systemName: "bolt.fill")
                        .foregroundStyle(tuningEnabled ? .yellow : .gray)
                    Text("Enable Tuning")
                }
            }
            
            if tuningEnabled {
                // Frequency
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Frequency")
                        Spacer()
                        Text("\(frequency) MHz")
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.blue)
                    }
                    
                    HStack {
                        Button {
                            if frequency > frequencyRange.lowerBound {
                                frequency -= 25
                                hasChanges = true
                            }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .font(.title2)
                        }
                        .buttonStyle(.borderless)
                        
                        Slider(
                            value: Binding(
                                get: { Double(frequency) },
                                set: { frequency = Int($0); hasChanges = true }
                            ),
                            in: Double(frequencyRange.lowerBound)...Double(frequencyRange.upperBound),
                            step: 25
                        )
                        
                        Button {
                            if frequency < frequencyRange.upperBound {
                                frequency += 25
                                hasChanges = true
                            }
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                        }
                        .buttonStyle(.borderless)
                    }
                }
                
                // Core Voltage
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Core Voltage")
                        Spacer()
                        Text("\(coreVoltage) mV")
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.orange)
                    }
                    
                    HStack {
                        Button {
                            if coreVoltage > voltageRange.lowerBound {
                                coreVoltage -= 10
                                hasChanges = true
                            }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .font(.title2)
                        }
                        .buttonStyle(.borderless)
                        
                        Slider(
                            value: Binding(
                                get: { Double(coreVoltage) },
                                set: { coreVoltage = Int($0); hasChanges = true }
                            ),
                            in: Double(voltageRange.lowerBound)...Double(voltageRange.upperBound),
                            step: 10
                        )
                        
                        Button {
                            if coreVoltage < voltageRange.upperBound {
                                coreVoltage += 10
                                hasChanges = true
                            }
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        } header: {
            Text("Performance")
        } footer: {
            if tuningEnabled {
                Label("Modifying these settings may affect miner stability. Use at your own risk.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        }
    }
    
    // MARK: - Cooling Section
    
    private var coolingSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { autoFanSpeed },
                set: { autoFanSpeed = $0; hasChanges = true }
            )) {
                Text("Auto Fan Speed")
            }
            
            if !autoFanSpeed {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Fan Speed")
                        Spacer()
                        Text("\(fanSpeed)%")
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.cyan)
                    }
                    
                    Slider(
                        value: Binding(
                            get: { Double(fanSpeed) },
                            set: { fanSpeed = Int($0); hasChanges = true }
                        ),
                        in: 0...100,
                        step: 5
                    )
                }
            }
            
            Toggle(isOn: Binding(
                get: { invertFanPolarity },
                set: { invertFanPolarity = $0; hasChanges = true }
            )) {
                Text("Invert Fan Polarity")
            }
        } header: {
            Text("Cooling")
        }
    }
    
    // MARK: - Display Section
    
    private var displaySection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { flipScreen },
                set: { flipScreen = $0; hasChanges = true }
            )) {
                Text("Flip Screen")
            }
            
            Toggle(isOn: Binding(
                get: { invertScreen },
                set: { invertScreen = $0; hasChanges = true }
            )) {
                Text("Invert Colors")
            }
        } header: {
            Text("Display")
        }
    }
    
    // MARK: - Danger Zone Section
    
    private var dangerZoneSection: some View {
        Section {
            Button(role: .destructive) {
                showRemoveAlert = true
            } label: {
                HStack {
                    Spacer()
                    Label("Remove Miner", systemImage: "trash")
                    Spacer()
                }
            }
        } header: {
            Text("Danger Zone")
        } footer: {
            Text("Removing the miner will stop monitoring and delete all stored data.")
        }
    }
    
    // MARK: - Actions
    
    private func loadCurrentSettings() async {
        isLoading = true
        defer { isLoading = false }
        
        let client = AxeOSClient(
            deviceIpAddress: miner.ipAddress,
            urlSession: .shared
        )
        
        let result = await client.getSystemInfo()
        
        if case .success(let info) = result {
            await MainActor.run {
                // Current values
                currentFrequency = Int(info.frequency ?? 500)
                currentVoltage = info.coreVoltage ?? 1200
                currentFanSpeed = Int(info.fanspeed ?? 100)
                currentAutoFan = (info.autofanspeed ?? 1) == 1
                
                // Editable values
                frequency = Int(info.frequency ?? 500)
                coreVoltage = info.coreVoltage ?? 1200
                fanSpeed = Int(info.fanspeed ?? 100)
                autoFanSpeed = (info.autofanspeed ?? 1) == 1
                flipScreen = (info.flipscreen ?? 0) == 1
                invertScreen = (info.invertscreen ?? 0) == 1
                invertFanPolarity = (info.invertfanpolarity ?? 0) == 1
                
                // Pool settings
                stratumURL = info.stratumURL ?? ""
                stratumPort = String(info.stratumPort ?? 0)
                stratumUser = info.stratumUser ?? ""
                // Password is not returned by the API for security
                
                // Load tuning enabled state
                tuningEnabled = UserDefaults.standard.bool(forKey: "tuningEnabled_\(miner.macAddress)")
            }
        }
    }
    
    private func saveSettings() async {
        isSaving = true
        errorMessage = ""
        
        defer { isSaving = false }
        
        // Save tuning state to UserDefaults
        UserDefaults.standard.set(tuningEnabled, forKey: "tuningEnabled_\(miner.macAddress)")
        
        let client = AxeOSClient(
            deviceIpAddress: miner.ipAddress,
            urlSession: .shared
        )
        
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
            hostname: nil,
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
                
                // Update current values
                currentFrequency = frequency
                currentVoltage = coreVoltage
                currentFanSpeed = fanSpeed
                currentAutoFan = autoFanSpeed
                
                showSuccessAlert = true
                
            case .failure(let error):
                errorMessage = "Failed to save settings: \(error.localizedDescription)"
                showErrorAlert = true
            }
        }
    }
    
    private func removeMiner() {
        // Delete associated MinerUpdate records first to prevent orphaned relationships
        let macAddress = miner.macAddress
        let updateDescriptor = FetchDescriptor<MinerUpdate>(
            predicate: #Predicate<MinerUpdate> { $0.macAddress == macAddress }
        )
        
        do {
            let updates = try modelContext.fetch(updateDescriptor)
            for update in updates {
                modelContext.delete(update)
            }
        } catch {
            print("Error cleaning up miner updates: \(error)")
        }
        
        // Delete the miner
        modelContext.delete(miner)
        
        // Save context to ensure clean state
        do {
            try modelContext.save()
        } catch {
            print("Error saving after miner deletion: \(error)")
        }
        
        // Dismiss and close
        dismiss()
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
