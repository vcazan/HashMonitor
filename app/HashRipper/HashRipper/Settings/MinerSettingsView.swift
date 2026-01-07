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
    @State private var currentFrequency: Double = 0
    @State private var currentVoltage: Double = 0
    @State private var currentFanSpeed: Double = 0
    @State private var currentAutoFan: Bool = true
    
    // Editable settings
    @State private var frequency: Double = 500
    @State private var coreVoltage: Double = 1200
    @State private var fanSpeed: Double = 100
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
    
    // Miner type specific limits
    private var frequencyRange: ClosedRange<Double> {
        switch miner.minerType {
        case .BitaxeGamma, .BitaxeGammaTurbo:
            return 400...650
        case .BitaxeSupra:
            return 400...650
        case .BitaxeUltra:
            return 400...600
        case .NerdQAxePlus, .NerdQAxePlusPlus:
            return 400...625
        case .NerdOCTAXE:
            return 400...600
        case .NerdQX:
            return 400...600
        default:
            return 400...600
        }
    }
    
    private var voltageRange: ClosedRange<Double> {
        switch miner.minerType {
        case .BitaxeGamma, .BitaxeGammaTurbo, .BitaxeSupra:
            return 1100...1300
        case .BitaxeUltra:
            return 1100...1250
        case .NerdQAxePlus, .NerdQAxePlusPlus:
            return 1100...1300
        default:
            return 1100...1300
        }
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
                    VStack(spacing: 24) {
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
        .frame(width: 500, height: 650)
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
    
    // MARK: - Current Status Card
    
    private var currentStatusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Current Status", systemImage: "gauge.with.dots.needle.bottom.50percent")
                .font(.headline)
            
            HStack(spacing: 20) {
                StatusItem(
                    icon: "speedometer",
                    label: "Frequency",
                    value: "\(Int(currentFrequency)) MHz",
                    color: .blue
                )
                
                StatusItem(
                    icon: "bolt.fill",
                    label: "Voltage",
                    value: "\(Int(currentVoltage)) mV",
                    color: .orange
                )
                
                StatusItem(
                    icon: "fan.fill",
                    label: "Fan",
                    value: currentAutoFan ? "Auto" : "\(Int(currentFanSpeed))%",
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
                    Text("Allows frequency and voltage adjustments beyond stock settings")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .onChange(of: overclockEnabled) { _, _ in hasChanges = true }
            
            Divider()
            
            // Frequency Slider
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Frequency")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                    Text("\(Int(frequency)) MHz")
                        .font(.system(.subheadline, design: .monospaced))
                        .fontWeight(.semibold)
                        .foregroundStyle(.blue)
                }
                
                Slider(value: $frequency, in: frequencyRange, step: 25) {
                    Text("Frequency")
                }
                .onChange(of: frequency) { _, _ in hasChanges = true }
                
                HStack {
                    Text("\(Int(frequencyRange.lowerBound))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(frequencyRange.upperBound)) MHz")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            
            // Voltage Slider
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Core Voltage")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                    Text("\(Int(coreVoltage)) mV")
                        .font(.system(.subheadline, design: .monospaced))
                        .fontWeight(.semibold)
                        .foregroundStyle(.orange)
                }
                
                Slider(value: $coreVoltage, in: voltageRange, step: 10) {
                    Text("Voltage")
                }
                .onChange(of: coreVoltage) { _, _ in hasChanges = true }
                
                HStack {
                    Text("\(Int(voltageRange.lowerBound))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(voltageRange.upperBound)) mV")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
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
                    Text("Let the miner control fan speed based on temperature")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .onChange(of: autoFanSpeed) { _, _ in hasChanges = true }
            
            if !autoFanSpeed {
                Divider()
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Fan Speed")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Spacer()
                        Text("\(Int(fanSpeed))%")
                            .font(.system(.subheadline, design: .monospaced))
                            .fontWeight(.semibold)
                            .foregroundStyle(.cyan)
                    }
                    
                    Slider(value: $fanSpeed, in: 0...100, step: 5) {
                        Text("Fan Speed")
                    }
                    .onChange(of: fanSpeed) { _, _ in hasChanges = true }
                    
                    HStack {
                        Text("0%")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("100%")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            Toggle(isOn: $invertFanPolarity) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Invert Fan Polarity")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("Reverse fan direction (for certain fan types)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    // MARK: - Warning Card
    
    private var warningCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundStyle(.orange)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Overclock Warning")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text("Overclocking may cause instability, increased heat, and potential hardware damage. Use at your own risk. Start with small increments and monitor temperatures closely.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
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
            // Load from latest MinerUpdate
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
                    if let latestUpdate = updates.first {
                        currentFrequency = latestUpdate.frequency ?? 500
                        currentVoltage = latestUpdate.voltage ?? 1200
                        currentFanSpeed = latestUpdate.fanspeed ?? 100
                        currentAutoFan = true // API doesn't return this, assume auto
                        
                        // Set editable values to current
                        frequency = currentFrequency
                        coreVoltage = currentVoltage
                        fanSpeed = currentFanSpeed
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
                hostname: nil,
                coreVoltage: Int(coreVoltage),
                frequency: Int(frequency),
                flipscreen: flipScreen ? 1 : 0,
                overheatMode: nil,
                overclockEnabled: overclockEnabled ? 1 : 0,
                invertscreen: invertScreen ? 1 : 0,
                invertfanpolarity: invertFanPolarity ? 1 : 0,
                autofanspeed: autoFanSpeed ? 1 : 0,
                fanspeed: autoFanSpeed ? nil : Int(fanSpeed)
            )
            
            let result = await client.updateSystemSettings(settings: settings)
            
            await MainActor.run {
                isSaving = false
                
                switch result {
                case .success:
                    showSuccessAlert = true
                case .failure(let error):
                    errorMessage = "Failed to apply settings: \(error)"
                    showErrorAlert = true
                }
            }
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

