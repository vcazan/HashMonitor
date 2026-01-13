//
//  MinerSettingsSheet.swift
//  HashMonitor
//
//  Apple Design Language - Settings inspired
//

import SwiftUI
import SwiftData
import HashRipperKit
import AxeOSClient
import AvalonClient

struct MinerSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var miner: Miner
    var onDelete: (() -> Void)? = nil
    
    // Settings state
    @State private var hostname: String = ""
    @State private var frequency: Double = 575
    @State private var voltage: Double = 1200
    @State private var fanSpeed: Double = 100
    @State private var autoFan: Bool = true
    @State private var invertFanPolarity: Bool = false
    
    // Display settings
    @State private var flipScreen: Bool = false
    @State private var invertScreen: Bool = false
    
    // Pool settings
    @State private var poolURL: String = ""
    @State private var poolPort: String = "3333"
    @State private var poolUser: String = ""
    @State private var poolPassword: String = ""
    
    // UI state
    @State private var isSaving = false
    @State private var showSaveSuccess = false
    @State private var showRemoveConfirmation = false
    @State private var showRemovedAlert = false
    @State private var showRestartConfirmation = false
    @State private var hasChanges = false
    @State private var latestUpdate: MinerUpdate?
    
    private let session = URLSession.shared
    
    // Constraints
    private let frequencyRange: ClosedRange<Double> = 495...1000
    private let voltageRange: ClosedRange<Double> = 1085...1350
    private let fanRange: ClosedRange<Double> = 0...100
    
    var body: some View {
        NavigationStack {
            settingsContent
        }
    }
    
    private var settingsContent: some View {
        scrollContent
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .alert("Remove Miner?", isPresented: $showRemoveConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Remove", role: .destructive) {
                    removeMiner()
                }
            } message: {
                Text("Are you sure you want to remove \"\(miner.hostName)\"? This cannot be undone.")
            }
            .alert("Miner Removed", isPresented: $showRemovedAlert) {
                removedAlertButton
            } message: {
                Text("The miner has been removed from your list.")
            }
            .alert("Restart Miner?", isPresented: $showRestartConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Restart", role: .destructive) {
                    Task { await restartMiner() }
                }
            } message: {
                Text("Are you sure you want to restart \"\(miner.hostName)\"? The miner will be temporarily offline while it reboots.")
            }
            .overlay { saveOverlay }
            .task { loadCurrentSettings() }
            .onChange(of: settingsHash) { _, _ in hasChanges = true }
    }
    
    // Track if any settings changed by hashing all values
    private var settingsHash: Int {
        var hasher = Hasher()
        hasher.combine(hostname)
        hasher.combine(frequency)
        hasher.combine(voltage)
        hasher.combine(fanSpeed)
        hasher.combine(autoFan)
        hasher.combine(invertFanPolarity)
        hasher.combine(flipScreen)
        hasher.combine(invertScreen)
        hasher.combine(poolURL)
        hasher.combine(poolPort)
        hasher.combine(poolUser)
        hasher.combine(poolPassword)
        return hasher.finalize()
    }
    
    private var removedAlertButton: some View {
        Button("OK") {
            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                onDelete?()
            }
        }
    }
    
    @ViewBuilder
    private var saveOverlay: some View {
        if showSaveSuccess {
            saveSuccessOverlay
        }
    }
    
    private var scrollContent: some View {
        ZStack {
            AppColors.backgroundGrouped
                .ignoresSafeArea()
            
            ScrollView {
                LazyVStack(spacing: Spacing.xl) {
                    deviceSection
                    
                    // Avalon miners - show available CGMiner API settings
                    if miner.isAvalonMiner {
                        avalonInfoSection
                        avalonFanSection
                        avalonPerformanceSection
                        avalonApplySection
                    } else {
                        performanceSection
                        displaySection
                        poolSection
                    }
                    
                    dangerSection
                }
                .padding()
            }
        }
    }
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(miner.isAvalonMiner ? "Done" : "Cancel") { dismiss() }
        }
        
        // Only show save button for AxeOS miners (Avalon has no editable settings)
        if !miner.isAvalonMiner {
            ToolbarItem(placement: .primaryAction) {
                if hasChanges {
                    Button {
                        Haptics.impact(.medium)
                        Task { await saveSettings() }
                    } label: {
                        if isSaving {
                            ProgressView()
                                .tint(.teal)
                        } else {
                            Text("Save")
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(isSaving)
                }
            }
        }
    }
    
    // MARK: - Device Section
    
    private var deviceSection: some View {
        SettingsSection(title: "Device", icon: "cpu") {
            VStack(spacing: 1) {
                if miner.isAvalonMiner {
                    // Avalon miners: hostname is read-only (can't be changed via API)
                    SettingsInfoRow(
                        label: "Hostname",
                        value: miner.hostName
                    )
                } else {
                    SettingsTextField(
                        label: "Hostname",
                        placeholder: "BitAxe",
                        text: $hostname
                    )
                }
                
                SettingsInfoRow(
                    label: "IP Address",
                    value: miner.ipAddress
                )
                
                if !miner.isAvalonMiner {
                    SettingsInfoRow(
                        label: "MAC Address",
                        value: miner.macAddress
                    )
                }
                
                SettingsInfoRow(
                    label: "Model",
                    value: miner.minerDeviceDisplayName
                )
                
                if let update = latestUpdate {
                    SettingsInfoRow(
                        label: "Firmware",
                        value: update.minerFirmwareVersion
                    )
                }
            }
        }
    }
    
    // MARK: - Avalon Info Section (Read-only)
    
    @State private var avalonFanSpeed: Double = 100
    @State private var avalonPerformanceMode: String = "normal"
    @State private var isApplyingAvalonSettings: Bool = false
    @State private var showAvalonApplySuccess: Bool = false
    
    private var avalonInfoSection: some View {
        SettingsSection(title: "Mining Info", icon: "chart.bar.fill") {
            VStack(spacing: 1) {
                if let update = latestUpdate {
                    SettingsInfoRow(
                        label: "Pool",
                        value: update.stratumURL.isEmpty ? "—" : update.stratumURL
                    )
                    
                    SettingsInfoRow(
                        label: "Worker",
                        value: update.stratumUser.isEmpty ? "—" : update.stratumUser
                    )
                    
                    SettingsInfoRow(
                        label: "Hash Rate",
                        value: formatHashRate(update.hashRate)
                    )
                    
                    SettingsInfoRow(
                        label: "Power",
                        value: String(format: "%.0f W", update.power)
                    )
                    
                    SettingsInfoRow(
                        label: "Uptime",
                        value: formatUptime(update.uptimeSeconds ?? 0)
                    )
                }
            }
        }
    }
    
    // MARK: - Avalon Fan Control Section
    
    private var avalonFanSection: some View {
        SettingsSection(title: "Fan Control", icon: "fan.fill") {
            VStack(spacing: Spacing.lg) {
                SettingsSlider(
                    label: "Fan Speed",
                    value: $avalonFanSpeed,
                    range: 0...100,
                    step: 5,
                    unit: "%",
                    color: AppColors.efficiency
                )
            }
            .padding(Spacing.lg)
        }
        .onAppear {
            if let update = latestUpdate {
                avalonFanSpeed = update.fanspeed ?? 100
            }
        }
    }
    
    // MARK: - Avalon Performance Section
    
    private var avalonPerformanceSection: some View {
        SettingsSection(title: "Performance", icon: "gauge.with.dots.needle.67percent") {
            VStack(spacing: Spacing.md) {
                Picker("Mode", selection: $avalonPerformanceMode) {
                    Text("Low Power").tag("low")
                    Text("Normal").tag("normal")
                    Text("High").tag("high")
                }
                .pickerStyle(.segmented)
                
                Text("Higher modes increase hash rate but also power and heat")
                    .font(.caption)
                    .foregroundStyle(AppColors.textTertiary)
            }
            .padding(Spacing.lg)
        }
    }
    
    // MARK: - Avalon Apply Settings Section
    
    private var avalonApplySection: some View {
        SettingsSection(title: "Apply Changes", icon: "checkmark.circle") {
            VStack(spacing: Spacing.md) {
                Button {
                    Haptics.impact(.medium)
                    Task { await applyAvalonSettings() }
                } label: {
                    HStack {
                        if isApplyingAvalonSettings {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Apply Settings")
                                .fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.md)
                }
                .buttonStyle(.borderedProminent)
                .tint(.teal)
                .disabled(isApplyingAvalonSettings)
                
                Text("Fan speed and performance mode will be sent to the miner")
                    .font(.caption)
                    .foregroundStyle(AppColors.textTertiary)
            }
            .padding(Spacing.lg)
        }
    }
    
    private func applyAvalonSettings() async {
        isApplyingAvalonSettings = true
        
        let client = AvalonClient(deviceIpAddress: miner.ipAddress, timeout: 5.0)
        
        // Apply fan speed
        let _ = await client.setFanSpeed(percent: Int(avalonFanSpeed))
        
        // Apply performance mode
        let _ = await client.setPerformanceMode(mode: avalonPerformanceMode)
        
        await MainActor.run {
            isApplyingAvalonSettings = false
            Haptics.notification(.success)
        }
    }
    
    private func formatHashRate(_ ghPerSec: Double) -> String {
        if ghPerSec >= 1000 {
            return String(format: "%.2f TH/s", ghPerSec / 1000)
        } else {
            return String(format: "%.0f GH/s", ghPerSec)
        }
    }
    
    private func formatUptime(_ seconds: Int) -> String {
        let days = seconds / 86400
        let hours = (seconds % 86400) / 3600
        let minutes = (seconds % 3600) / 60
        
        if days > 0 {
            return "\(days)d \(hours)h"
        } else if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
    
    // MARK: - Performance Section
    
    private var performanceSection: some View {
        SettingsSection(title: "Performance", icon: "gauge.with.dots.needle.67percent") {
            VStack(spacing: Spacing.lg) {
                // Frequency
                SettingsSlider(
                    label: "Frequency",
                    value: $frequency,
                    range: frequencyRange,
                    step: 5,
                    unit: "MHz",
                    color: AppColors.frequency
                )
                
                Divider()
                
                // Voltage
                SettingsSlider(
                    label: "Core Voltage",
                    value: $voltage,
                    range: voltageRange,
                    step: 5,
                    unit: "mV",
                    color: AppColors.power
                )
                
                Divider()
                
                // Fan
                Toggle(isOn: $autoFan) {
                    HStack {
                        Image(systemName: "fan.fill")
                            .foregroundStyle(AppColors.efficiency)
                        Text("Auto Fan")
                            .font(.bodyMedium)
                    }
                }
                .tint(.teal)
                
                if !autoFan {
                    SettingsSlider(
                        label: "Fan Speed",
                        value: $fanSpeed,
                        range: fanRange,
                        step: 5,
                        unit: "%",
                        color: AppColors.efficiency
                    )
                }
                
                Divider()
                
                // Invert Fan Polarity
                Toggle(isOn: $invertFanPolarity) {
                    HStack {
                        Image(systemName: "arrow.left.arrow.right")
                            .foregroundStyle(AppColors.textTertiary)
                        Text("Invert Fan Polarity")
                            .font(.bodyMedium)
                    }
                }
                .tint(.teal)
            }
            .padding(Spacing.lg)
        }
    }
    
    // MARK: - Display Section
    
    private var displaySection: some View {
        SettingsSection(title: "Display", icon: "display") {
            VStack(spacing: Spacing.md) {
                Toggle(isOn: $flipScreen) {
                    HStack {
                        Image(systemName: "arrow.up.arrow.down")
                            .foregroundStyle(AppColors.textTertiary)
                        Text("Flip Screen")
                            .font(.bodyMedium)
                    }
                }
                .tint(.teal)
                
                Toggle(isOn: $invertScreen) {
                    HStack {
                        Image(systemName: "circle.lefthalf.filled")
                            .foregroundStyle(AppColors.textTertiary)
                        Text("Invert Screen Colors")
                            .font(.bodyMedium)
                    }
                }
                .tint(.teal)
            }
            .padding(Spacing.lg)
        }
    }
    
    // MARK: - Pool Section
    
    private var poolSection: some View {
        SettingsSection(title: "Mining Pool", icon: "network") {
            VStack(spacing: 1) {
                SettingsTextField(
                    label: "Pool URL",
                    placeholder: "stratum+tcp://pool.example.com",
                    text: $poolURL
                )
                
                SettingsTextField(
                    label: "Port",
                    placeholder: "3333",
                    text: $poolPort,
                    keyboardType: .numberPad
                )
                
                SettingsTextField(
                    label: "Worker",
                    placeholder: "your_wallet.worker",
                    text: $poolUser
                )
                
                SettingsTextField(
                    label: "Password",
                    placeholder: "x",
                    text: $poolPassword,
                    isSecure: true
                )
            }
        }
    }
    
    // MARK: - Danger Section
    
    private var dangerSection: some View {
        SettingsSection(title: "Actions", icon: "exclamationmark.triangle") {
            VStack(spacing: 1) {
                Button {
                    Haptics.impact(.medium)
                    showRestartConfirmation = true
                } label: {
                    SettingsButtonRow(
                        label: "Restart Miner",
                        icon: "arrow.clockwise",
                        color: .orange
                    )
                }
                .buttonStyle(.plain)
                
                Button {
                    Haptics.impact(.heavy)
                    showRemoveConfirmation = true
                } label: {
                    SettingsButtonRow(
                        label: "Remove Miner",
                        icon: "trash",
                        color: AppColors.statusOffline
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    // MARK: - Save Success Overlay
    
    private var saveSuccessOverlay: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(AppColors.statusOnline)
            
            Text("Settings Saved")
                .font(.titleSmall)
                .foregroundStyle(AppColors.textPrimary)
        }
        .padding(Spacing.xxl)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .transition(.scale.combined(with: .opacity))
    }
    
    // MARK: - Functions
    
    private func loadCurrentSettings() {
        hostname = miner.hostName
        latestUpdate = miner.getLatestUpdate(from: modelContext)
        
        if let update = latestUpdate {
            frequency = update.frequency ?? 575
            voltage = Double(update.coreVoltage ?? 1200)
            fanSpeed = update.fanspeed ?? 100
            autoFan = update.autofanspeed == 1
            invertFanPolarity = update.invertfanpolarity == 1
            
            // Display settings
            flipScreen = update.flipscreen == 1
            invertScreen = update.invertscreen == 1
            
            poolURL = update.stratumURL
            poolPort = String(update.stratumPort)
            poolUser = update.stratumUser
            poolPassword = ""
        }
        
        hasChanges = false
    }
    
    private func saveSettings() async {
        isSaving = true
        
        let client = AxeOSClient(deviceIpAddress: miner.ipAddress, urlSession: session)
        
        // Build the settings object with all current values
        let settings = MinerSettings(
            stratumURL: poolURL,
            fallbackStratumURL: nil,
            stratumUser: poolUser,
            stratumPassword: poolPassword.isEmpty ? "x" : poolPassword,
            fallbackStratumUser: nil,
            fallbackStratumPassword: nil,
            stratumPort: Int(poolPort) ?? 3333,
            fallbackStratumPort: nil,
            ssid: nil,
            wifiPass: nil,
            hostname: hostname,
            coreVoltage: Int(voltage),
            frequency: Int(frequency),
            flipscreen: flipScreen ? 1 : 0,
            overheatMode: nil,
            overclockEnabled: nil,
            invertscreen: invertScreen ? 1 : 0,
            invertfanpolarity: invertFanPolarity ? 1 : 0,
            autofanspeed: autoFan ? 1 : 0,
            fanspeed: autoFan ? nil : Int(fanSpeed)
        )
        
        let result = await client.updateSystemSettings(settings: settings)
        
        switch result {
        case .success:
            // Update local miner hostname if changed
            if hostname != miner.hostName {
                miner.hostName = hostname
            }
            
            // Refresh data from miner to update local cache
            let refreshResult = await client.getSystemInfo()
            if case .success(let info) = refreshResult {
                let update = MinerUpdate.from(miner: miner, info: info)
                await MainActor.run {
                    modelContext.insert(update)
                    try? modelContext.save()
                }
            }
            
            await MainActor.run {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    showSaveSuccess = true
                }
                Haptics.notification(.success)
                hasChanges = false
            }
            
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            
            await MainActor.run {
                withAnimation {
                    showSaveSuccess = false
                }
                dismiss()
            }
            
        case .failure:
            await MainActor.run {
                Haptics.notification(.error)
            }
        }
        
        isSaving = false
    }
    
    private func restartMiner() async {
        if miner.isAvalonMiner {
            let client = AvalonClient(deviceIpAddress: miner.ipAddress, timeout: 5.0)
            let result = await client.restart()
            switch result {
            case .success:
                Haptics.notification(.success)
            case .failure:
                Haptics.notification(.error)
            }
        } else {
            let client = AxeOSClient(deviceIpAddress: miner.ipAddress, urlSession: session)
            let result = await client.restartClient()
            switch result {
            case .success:
                Haptics.notification(.success)
            case .failure:
                Haptics.notification(.error)
            }
        }
    }
    
    private func removeMiner() {
        // Delete miner - cascade rule will delete all associated MinerUpdates
        modelContext.delete(miner)
        
        do {
            try modelContext.save()
            Haptics.notification(.success)
            showRemovedAlert = true
        } catch {
            print("Failed to delete miner: \(error)")
            Haptics.notification(.error)
        }
    }
}

// MARK: - Settings Section

struct SettingsSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: () -> Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.teal)
                
                Text(title.uppercased())
                    .font(.captionMedium)
                    .foregroundStyle(AppColors.textSecondary)
                    .tracking(0.5)
            }
            .padding(.horizontal, Spacing.xs)
            
            content()
                .background(
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .fill(AppColors.backgroundGroupedSecondary)
                )
        }
    }
}

// MARK: - Settings Text Field

struct SettingsTextField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default
    var isSecure: Bool = false
    
    var body: some View {
        HStack {
            Text(label)
                .font(.bodyMedium)
                .foregroundStyle(AppColors.textPrimary)
            
            Spacer()
            
            if isSecure {
                SecureField(placeholder, text: $text)
                    .font(.bodyMedium)
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 180)
            } else {
                TextField(placeholder, text: $text)
                    .font(.bodyMedium)
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(keyboardType)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .frame(maxWidth: 180)
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.md)
    }
}

// MARK: - Settings Info Row

struct SettingsInfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.bodyMedium)
                .foregroundStyle(AppColors.textPrimary)
            
            Spacer()
            
            Text(value)
                .font(.bodyMedium)
                .foregroundStyle(AppColors.textTertiary)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.md)
    }
}

// MARK: - Settings Slider

struct SettingsSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let unit: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text(label)
                    .font(.bodyMedium)
                    .foregroundStyle(AppColors.textPrimary)
                
                Spacer()
                
                Text("\(Int(value)) \(unit)")
                    .font(.numericSmall)
                    .foregroundStyle(color)
                    .contentTransition(.numericText())
            }
            
            Slider(value: $value, in: range, step: step) { _ in
                Haptics.selection()
            }
            .tint(color)
        }
    }
}

// MARK: - Settings Button Row

struct SettingsButtonRow: View {
    let label: String
    let icon: String
    let color: Color
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(color)
                .frame(width: 24)
            
            Text(label)
                .font(.bodyMedium)
                .foregroundStyle(color)
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppColors.textQuaternary)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.md)
    }
}

// MARK: - Preview

#Preview {
    MinerSettingsSheet(miner: Miner(
        hostName: "BitAxe-Ultra",
        ipAddress: "192.168.1.100",
        ASICModel: "BM1366",
        macAddress: "AA:BB:CC:DD:EE:FF"
    ))
    .modelContainer(for: [Miner.self, MinerUpdate.self], inMemory: true)
}
