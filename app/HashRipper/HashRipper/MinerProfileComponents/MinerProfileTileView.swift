//
//  MinerProfileTileView.swift
//  HashRipper
//
//  Created by Matt Sellars
//
import SwiftUI

struct MinerProfileTileView: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.modelContext) var modelContext

    @State private var showDeleteConfirmation: Bool = false
    @State private var showDuplicateProfileForm: Bool = false
    @State private var showNewProfileSavedAlert: Bool = false
    @State private var showEditProfileSheet: Bool = false
    @State private var showShareSheet: Bool = false
    @State private var exportedProfileData: Data?
    @State private var shareAlertMessage = ""
    @State private var showShareAlert = false
    @State private var verificationStatus: PoolVerificationStatus?
    @State private var showVerificationWizard = false

    var minerProfile: MinerProfileTemplate
    var showOptionalActions: Bool
    var minerName: String?
    var handleDeployProfile: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerSection
            primaryPoolSection
            fallbackPoolSection
            
            if showOptionalActions {
                actionsSection
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
        .task {
            verificationStatus = await minerProfile.verificationStatus(context: modelContext)
        }
        .alert("Delete Profile?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                modelContext.delete(minerProfile)
                try? modelContext.save()
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Profile saved", isPresented: $showNewProfileSavedAlert) {
            Button("OK") {}
        }
        .alert("Profile Export", isPresented: $showShareAlert) {
            Button("OK") {}
        } message: {
            Text(shareAlertMessage)
        }
        .fileExporter(
            isPresented: $showShareSheet,
            document: JSONDocument(data: exportedProfileData ?? Data()),
            contentType: .json,
            defaultFilename: "profile-\(minerProfile.name.replacingOccurrences(of: " ", with: "-").lowercased())"
        ) { result in
            handleExportResult(result)
        }
        .sheet(isPresented: $showEditProfileSheet) {
            MinerProfileTemplateFormView(
                existingProfile: minerProfile,
                onSave: { _ in showEditProfileSheet = false },
                onCancel: { showEditProfileSheet = false }
            )
        }
        .sheet(isPresented: $showVerificationWizard) {
            PoolVerificationWizard(profile: minerProfile)
        }
    }
    
    // MARK: - Header
    
    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(minerProfile.name)
                    .font(.headline)
                    .fontWeight(.semibold)
                
                if !minerProfile.templateNotes.isEmpty {
                    Text(minerProfile.templateNotes)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()

            if let status = verificationStatus {
                PoolVerificationBadge(status: status)
                    .onTapGesture { showVerificationWizard = true }
            } else {
                Button(action: { showVerificationWizard = true }) {
                    Label("Verify Pool", systemImage: "shield")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
            }

            Image(systemName: "server.rack")
                .font(.title2)
                .foregroundColor(.accentColor)
        }
    }
    
    // MARK: - Primary Pool
    
    private var primaryPoolSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Primary Pool", systemImage: "globe")
                .font(.subheadline)
                .fontWeight(.medium)

            VStack(alignment: .leading, spacing: 4) {
                PoolDetailRow(label: "URL", value: minerProfile.stratumURL)
                PoolDetailRow(label: "Port", value: String(minerProfile.stratumPort))
                PoolDetailRow(label: "User", value: primaryPoolUser)
            }
            .padding(.leading, 16)
        }
    }
    
    private var primaryPoolUser: String {
        let name = minerName ?? "<miner-name>"
        if minerProfile.isPrimaryPoolParasite {
            let lightning = minerProfile.parasiteLightningAddress ?? "no-lightning-address"
            return "\(minerProfile.poolAccount).\(name).\(lightning)@parasite.sati.pro"
        } else {
            return "\(minerProfile.poolAccount).\(name)"
        }
    }
    
    // MARK: - Fallback Pool
    
    @ViewBuilder
    private var fallbackPoolSection: some View {
        if let url = minerProfile.fallbackStratumURL,
           let port = minerProfile.fallbackStratumPort,
           let account = minerProfile.fallbackStratumAccount {
            VStack(alignment: .leading, spacing: 8) {
                Label("Fallback Pool", systemImage: "arrow.triangle.2.circlepath")
                    .font(.subheadline)
                    .fontWeight(.medium)

                VStack(alignment: .leading, spacing: 4) {
                    PoolDetailRow(label: "URL", value: url)
                    PoolDetailRow(label: "Port", value: String(port))
                    PoolDetailRow(label: "User", value: fallbackPoolUser(account: account))
                }
                .padding(.leading, 16)
            }
        }
    }
    
    private func fallbackPoolUser(account: String) -> String {
        let name = minerName ?? "<miner-name>"
        if minerProfile.isFallbackPoolParasite {
            let lightning = minerProfile.fallbackParasiteLightningAddress ?? "no-lightning-address"
            return "\(account).\(name).\(lightning)@parasite.sati.pro"
        } else {
            return "\(account).\(name)"
        }
    }
    
    // MARK: - Actions
    
    private var actionsSection: some View {
        Group {
            Divider()

            HStack(spacing: 12) {
                if let deploy = handleDeployProfile {
                    Button(action: deploy) {
                        Label("Deploy", systemImage: "iphone.and.arrow.forward.inward")
                    }
                    .buttonStyle(.borderedProminent)
                    .help("Deploy this profile to miners")
                }

                Spacer()

                HStack(spacing: 8) {
                    Button(action: shareProfile) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .help("Share this profile")

                    Button(action: { showEditProfileSheet = true }) {
                        Image(systemName: "pencil")
                    }
                    .help("Edit this profile")

                    Button(action: { showDeleteConfirmation = true }) {
                        Image(systemName: "trash")
                    }
                    .foregroundColor(.red)
                    .help("Delete this profile")
                }
                .buttonStyle(.bordered)
            }
        }
    }
    
    // MARK: - Actions
    
    private func shareProfile() {
        do {
            let data = try ProfileJSONExporter.exportSingleProfile(minerProfile)
            exportedProfileData = data
            showShareSheet = true
        } catch {
            shareAlertMessage = "Failed to export profile: \(error.localizedDescription)"
            showShareAlert = true
        }
    }
    
    private func handleExportResult(_ result: Result<URL, Error>) {
        switch result {
        case .success:
            shareAlertMessage = "Profile '\(minerProfile.name)' exported successfully!"
            showShareAlert = true
        case .failure(let error):
            shareAlertMessage = "Export failed: \(error.localizedDescription)"
            showShareAlert = true
        }
    }
}

// MARK: - Helper Views

private struct PoolDetailRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text("\(label):")
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.body.monospaced())
        }
    }
}
