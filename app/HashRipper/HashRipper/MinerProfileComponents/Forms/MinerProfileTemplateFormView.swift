import SwiftUI
import SwiftData

struct MinerProfileTemplateFormView: View {
    
    // MARK: - Environment
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    
    // MARK: - Mode
    private let existingProfile: MinerProfileTemplate?
    private var isEditing: Bool { existingProfile != nil }
    
    // MARK: - Form State
    @State private var name: String = ""
    @State private var templateNotes: String = ""
    
    // Primary pool
    @State private var stratumURL: String = ""
    @State private var stratumPort: String = ""
    @State private var poolAccount: String = ""
    @State private var stratumPassword: String = ""
    @State private var parasiteLightningAddress: String = ""
    
    // Fallback pool
    @State private var showFallback: Bool = false
    @State private var fallbackURL: String = ""
    @State private var fallbackPort: String = ""
    @State private var fallbackAccount: String = ""
    @State private var fallbackPassword: String = ""
    @State private var fallbackLightningAddress: String = ""
    
    // Callbacks
    let onSave: (MinerProfileTemplate) -> Void
    let onCancel: () -> Void
    
    // MARK: - Initializers
    
    init(onSave: @escaping (MinerProfileTemplate) -> Void, onCancel: @escaping () -> Void) {
        self.existingProfile = nil
        self.onSave = onSave
        self.onCancel = onCancel
    }
    
    init(existingProfile: MinerProfileTemplate, onSave: @escaping (MinerProfileTemplate) -> Void, onCancel: @escaping () -> Void) {
        self.existingProfile = existingProfile
        self.onSave = onSave
        self.onCancel = onCancel
        
        // Initialize state from existing profile
        _name = State(initialValue: existingProfile.name)
        _templateNotes = State(initialValue: existingProfile.templateNotes)
        _stratumURL = State(initialValue: existingProfile.stratumURL)
        _stratumPort = State(initialValue: existingProfile.stratumPort > 0 ? "\(existingProfile.stratumPort)" : "")
        _poolAccount = State(initialValue: existingProfile.poolAccount)
        _stratumPassword = State(initialValue: existingProfile.stratumPassword)
        _parasiteLightningAddress = State(initialValue: existingProfile.parasiteLightningAddress ?? "")
        
        let hasFallback = !(existingProfile.fallbackStratumURL ?? "").isEmpty
        _showFallback = State(initialValue: hasFallback)
        _fallbackURL = State(initialValue: existingProfile.fallbackStratumURL ?? "")
        _fallbackPort = State(initialValue: existingProfile.fallbackStratumPort.map { "\($0)" } ?? "")
        _fallbackAccount = State(initialValue: existingProfile.fallbackStratumAccount ?? "")
        _fallbackPassword = State(initialValue: existingProfile.fallbackStratumPassword ?? "")
        _fallbackLightningAddress = State(initialValue: existingProfile.fallbackParasiteLightningAddress ?? "")
    }
    
    // MARK: - Computed
    
    private var isPrimaryParasite: Bool {
        isParasitePool(stratumURL)
    }
    
    private var isFallbackParasite: Bool {
        isParasitePool(fallbackURL)
    }
    
    private var isFormValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !stratumURL.trimmingCharacters(in: .whitespaces).isEmpty &&
        (Int(stratumPort) ?? 0) > 0 &&
        !poolAccount.trimmingCharacters(in: .whitespaces).isEmpty &&
        !stratumPassword.trimmingCharacters(in: .whitespaces).isEmpty &&
        (!isPrimaryParasite || !parasiteLightningAddress.trimmingCharacters(in: .whitespaces).isEmpty)
    }
    
    // MARK: - Body
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
            
            Divider()
            
            // Form content
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Profile Info Section
                    FormSection(title: "Profile Info") {
                        FormField(label: "Name", required: true) {
                            TextField("e.g. Solo Mining - Ocean", text: $name)
                                .textFieldStyle(.roundedBorder)
                        }
                        
                        FormField(label: "Notes") {
                            TextField("Optional notes about this profile", text: $templateNotes, axis: .vertical)
                                .textFieldStyle(.roundedBorder)
                                .lineLimit(2...4)
                        }
                    }
                    
                    // Primary Pool Section
                    FormSection(title: "Primary Pool", badge: isPrimaryParasite ? "Parasite" : nil) {
                        HStack(spacing: 12) {
                            FormField(label: "Stratum URL", required: true) {
                                TextField("stratum.example.com", text: $stratumURL)
                                    .textFieldStyle(.roundedBorder)
                            }
                            
                            FormField(label: "Port", required: true) {
                                TextField("3333", text: $stratumPort)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 80)
                            }
                        }
                        
                        FormField(label: "Account / BTC Address", required: true) {
                            TextField("Your wallet address or pool username", text: $poolAccount)
                                .textFieldStyle(.roundedBorder)
                        }
                        
                        FormField(label: "Password", required: true) {
                            TextField("x", text: $stratumPassword)
                                .textFieldStyle(.roundedBorder)
                        }
                        
                        if isPrimaryParasite {
                            FormField(label: "Lightning Address", required: true) {
                                TextField("your@lightning.address", text: $parasiteLightningAddress)
                                    .textFieldStyle(.roundedBorder)
                            }
                            
                            parasiteHelpLink
                        }
                    }
                    
                    // Fallback Pool Section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Toggle("Add Fallback Pool", isOn: $showFallback.animation(.easeOut(duration: 0.2)))
                                .toggleStyle(.switch)
                                .controlSize(.small)
                            
                            if showFallback {
                                Spacer()
                                
                                Button(action: swapPools) {
                                    Label("Swap with Primary", systemImage: "arrow.up.arrow.down")
                                }
                                .buttonStyle(.borderless)
                                .font(.system(size: 12))
                                .foregroundStyle(.orange)
                            }
                        }
                        
                        if showFallback {
                            FormSection(title: "Fallback Pool", badge: isFallbackParasite ? "Parasite" : nil) {
                                HStack(spacing: 12) {
                                    FormField(label: "Stratum URL") {
                                        TextField("stratum.fallback.com", text: $fallbackURL)
                                            .textFieldStyle(.roundedBorder)
                                    }
                                    
                                    FormField(label: "Port") {
                                        TextField("3333", text: $fallbackPort)
                                            .textFieldStyle(.roundedBorder)
                                            .frame(width: 80)
                                    }
                                }
                                
                                FormField(label: "Account / BTC Address") {
                                    TextField("Your wallet address", text: $fallbackAccount)
                                        .textFieldStyle(.roundedBorder)
                                }
                                
                                FormField(label: "Password") {
                                    TextField("x", text: $fallbackPassword)
                                        .textFieldStyle(.roundedBorder)
                                }
                                
                                if isFallbackParasite {
                                    FormField(label: "Lightning Address") {
                                        TextField("your@lightning.address", text: $fallbackLightningAddress)
                                            .textFieldStyle(.roundedBorder)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(24)
            }
            
            Divider()
            
            // Footer
            footer
        }
        .frame(minWidth: 500, idealWidth: 600, maxWidth: 700, minHeight: 500, idealHeight: 600)
        .background(Color(nsColor: .windowBackgroundColor))
    }
    
    // MARK: - Subviews
    
    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(isEditing ? "Edit Profile" : "New Profile")
                    .font(.system(size: 16, weight: .semibold))
                
                Text(isEditing ? "Update pool configuration" : "Create a reusable pool configuration")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }
    
    private var footer: some View {
        HStack {
            Spacer()
            
            Button("Cancel", action: onCancel)
                .keyboardShortcut(.escape)
            
            Button(isEditing ? "Save Changes" : "Create Profile") {
                saveProfile()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return)
            .disabled(!isFormValid)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }
    
    private var parasiteHelpLink: some View {
        HStack(spacing: 4) {
            Image("parasiteIcon")
                .resizable()
                .frame(width: 14, height: 14)
            
            Link("Parasite Setup Guide", destination: URL(string: "https://www.solosatoshi.com/how-to-connect-your-bitaxe-to-parasite-pool/?from=HashMonitor")!)
                .font(.system(size: 11))
        }
        .padding(.top, 4)
    }
    
    // MARK: - Actions
    
    private func swapPools() {
        let tempURL = stratumURL
        let tempPort = stratumPort
        let tempAccount = poolAccount
        let tempPassword = stratumPassword
        let tempLightning = parasiteLightningAddress
        
        stratumURL = fallbackURL
        stratumPort = fallbackPort
        poolAccount = fallbackAccount
        stratumPassword = fallbackPassword
        parasiteLightningAddress = fallbackLightningAddress
        
        fallbackURL = tempURL
        fallbackPort = tempPort
        fallbackAccount = tempAccount
        fallbackPassword = tempPassword
        fallbackLightningAddress = tempLightning
    }
    
    private func saveProfile() {
        let portInt = Int(stratumPort) ?? 0
        guard portInt > 0 else { return }
        
        let hasFallback = showFallback &&
            !fallbackURL.trimmingCharacters(in: .whitespaces).isEmpty &&
            (Int(fallbackPort) ?? 0) > 0 &&
            !fallbackAccount.trimmingCharacters(in: .whitespaces).isEmpty &&
            !fallbackPassword.trimmingCharacters(in: .whitespaces).isEmpty
        
        if let existing = existingProfile {
            // Update existing profile
            existing.name = name.trimmingCharacters(in: .whitespaces)
            existing.templateNotes = templateNotes.trimmingCharacters(in: .whitespaces)
            existing.stratumURL = stratumURL.trimmingCharacters(in: .whitespaces)
            existing.stratumPort = portInt
            existing.poolAccount = poolAccount.trimmingCharacters(in: .whitespaces)
            existing.stratumPassword = stratumPassword.trimmingCharacters(in: .whitespaces)
            existing.parasiteLightningAddress = isPrimaryParasite ? parasiteLightningAddress.trimmingCharacters(in: .whitespaces) : nil
            
            if hasFallback {
                existing.fallbackStratumURL = fallbackURL.trimmingCharacters(in: .whitespaces)
                existing.fallbackStratumPort = Int(fallbackPort)
                existing.fallbackStratumAccount = fallbackAccount.trimmingCharacters(in: .whitespaces)
                existing.fallbackStratumPassword = fallbackPassword.trimmingCharacters(in: .whitespaces)
                existing.fallbackParasiteLightningAddress = isFallbackParasite ? fallbackLightningAddress.trimmingCharacters(in: .whitespaces) : nil
            } else {
                existing.fallbackStratumURL = nil
                existing.fallbackStratumPort = nil
                existing.fallbackStratumAccount = nil
                existing.fallbackStratumPassword = nil
                existing.fallbackParasiteLightningAddress = nil
            }
            
            try? modelContext.save()
            onSave(existing)
        } else {
            // Create new profile
            let template = MinerProfileTemplate(
                name: name.trimmingCharacters(in: .whitespaces),
                templateNotes: templateNotes.trimmingCharacters(in: .whitespaces),
                stratumURL: stratumURL.trimmingCharacters(in: .whitespaces),
                poolAccount: poolAccount.trimmingCharacters(in: .whitespaces),
                parasiteLightningAddress: isPrimaryParasite ? parasiteLightningAddress.trimmingCharacters(in: .whitespaces) : nil,
                stratumPort: portInt,
                stratumPassword: stratumPassword.trimmingCharacters(in: .whitespaces),
                fallbackStratumURL: hasFallback ? fallbackURL.trimmingCharacters(in: .whitespaces) : nil,
                fallbackStratumAccount: hasFallback ? fallbackAccount.trimmingCharacters(in: .whitespaces) : nil,
                fallbackParasiteLightningAddress: hasFallback && isFallbackParasite ? fallbackLightningAddress.trimmingCharacters(in: .whitespaces) : nil,
                fallbackStatrumPassword: hasFallback ? fallbackPassword.trimmingCharacters(in: .whitespaces) : nil,
                fallbackStratumPort: hasFallback ? Int(fallbackPort) : nil
            )
            
            modelContext.insert(template)
            try? modelContext.save()
            onSave(template)
        }
    }
}

// MARK: - Helper Views

private struct FormSection<Content: View>: View {
    let title: String
    var badge: String? = nil
    @ViewBuilder let content: Content
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                
                if let badge = badge {
                    Text(badge)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
            
            VStack(alignment: .leading, spacing: 14) {
                content
            }
            .padding(16)
            .background(colorScheme == .dark ? Color(white: 0.1) : .white)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(colorScheme == .dark ? Color(white: 0.15) : Color(white: 0.9), lineWidth: 1)
            )
        }
    }
}

private struct FormField<Content: View>: View {
    let label: String
    var required: Bool = false
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 2) {
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                
                if required {
                    Text("*")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.red)
                }
            }
            
            content
        }
    }
}
