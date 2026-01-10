//
//  MinerProfilesView.swift
//  HashRipper
//
//  Created by Matt Sellars
//

import SwiftData
import SwiftUI

struct MinerProfilesView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme

    @Query(sort: \MinerProfileTemplate.name) var minerProfiles: [MinerProfileTemplate]
    @State private var showAddProfileSheet: Bool = false
    @State private var showNewProfileSavedAlert: Bool = false
    @State private var showJSONManagement: Bool = false
    @State private var selectedProfile: MinerProfileTemplate? = nil
    @State private var searchText: String = ""
    @State private var deployProfile: MinerProfileTemplate? = nil
    @State private var editingProfile: MinerProfileTemplate? = nil

    private var filteredProfiles: [MinerProfileTemplate] {
        if searchText.isEmpty {
            return minerProfiles
        }
        let query = searchText.lowercased()
        return minerProfiles.filter { profile in
            profile.name.lowercased().contains(query) ||
            profile.stratumURL.lowercased().contains(query) ||
            profile.poolAccount.lowercased().contains(query)
        }
    }

    var body: some View {
        HSplitView {
            // Left: Profile List
            profileListPanel
                .frame(minWidth: 280, idealWidth: 320, maxWidth: 400)
            
            // Right: Detail View
            detailPanel
                .frame(minWidth: 500)
        }
        .sheet(isPresented: $showAddProfileSheet) {
            MinerProfileTemplateFormView(onSave: { newProfile in
                showAddProfileSheet = false
                showNewProfileSavedAlert = true
                selectedProfile = newProfile
            }, onCancel: { showAddProfileSheet = false })
        }
        .sheet(item: $editingProfile) { profile in
            MinerProfileTemplateFormView(
                existingProfile: profile,
                onSave: { updatedProfile in
                    editingProfile = nil
                    selectedProfile = updatedProfile
                },
                onCancel: { editingProfile = nil }
            )
        }
        .sheet(item: $deployProfile) { profile in
            MinerProfileRolloutWizard(onClose: {
                deployProfile = nil
            }, profile: profile)
        }
        .sheet(isPresented: $showJSONManagement) {
            ProfileJSONManagementView()
        }
        .alert("Profile saved", isPresented: $showNewProfileSavedAlert) {
            Button("OK") {}
        }
    }
    
    // MARK: - Profile List Panel
    
    private var profileListPanel: some View {
        VStack(spacing: 0) {
            // List header
            HStack(alignment: .center) {
                Text("Saved Profiles")
                    .font(.system(size: 13, weight: .semibold))
                
                Spacer()
                
                Text("\(filteredProfiles.count)")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(Capsule())
                
                Button(action: addNewProfile) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Create new profile")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            
            // Search field
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                
                TextField("Search profiles...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear search")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(colorScheme == .dark ? Color(white: 0.12) : Color(white: 0.95))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
            
            Divider()
            
            // Profile list
            if minerProfiles.isEmpty {
                // Empty state
                VStack(spacing: 12) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 32, weight: .thin))
                        .foregroundStyle(.quaternary)
                    
                    Text("No Profiles")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                    
                    Text("Click + to create your first profile")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 40)
            } else if filteredProfiles.isEmpty && !searchText.isEmpty {
                // No results state
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 24, weight: .thin))
                        .foregroundStyle(.quaternary)
                    Text("No profiles found")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Text("Try a different search term")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 40)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredProfiles) { profile in
                            ProfileListRow(
                                profile: profile,
                                isSelected: selectedProfile?.id == profile.id
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation(.easeOut(duration: 0.12)) {
                                    selectedProfile = profile
                                }
                            }
                            
                            if profile.id != filteredProfiles.last?.id {
                                Divider()
                                    .padding(.leading, 16)
                            }
                        }
                    }
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
    
    // MARK: - Detail Panel
    
    private var detailPanel: some View {
        Group {
            if let profile = selectedProfile {
                ProfileDetailView(
                    profile: profile,
                    onDeploy: { deployProfile = profile },
                    onEdit: { editingProfile = profile },
                    onDelete: {
                        modelContext.delete(profile)
                        try? modelContext.save()
                        selectedProfile = nil
                    }
                )
            } else {
                emptyDetailView
            }
        }
        .background(colorScheme == .dark ? Color(white: 0.08) : Color(white: 0.98))
    }
    
    private var emptyDetailView: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text")
                .font(.system(size: 48, weight: .ultraLight))
                .foregroundStyle(.quaternary)
            
            VStack(spacing: 4) {
                Text("Select a Profile")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                
                Text("Choose a profile from the list to view details")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }
            
            Button(action: { showJSONManagement = true }) {
                Label("Import JSON", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    func addNewProfile() {
        showAddProfileSheet = true
    }
}

// MARK: - Profile List Row

struct ProfileListRow: View {
    let profile: MinerProfileTemplate
    let isSelected: Bool
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: "doc.text.fill")
                .font(.system(size: 16))
                .foregroundStyle(.blue)
                .frame(width: 32, height: 32)
                .background(Color.blue.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            
            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                
                if !profile.stratumURL.isEmpty {
                    Text(profile.stratumURL)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text("No pool configured")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
            
            Spacer()
            
            // Has fallback indicator
            if profile.fallbackStratumURL != nil && !(profile.fallbackStratumURL ?? "").isEmpty {
                Image(systemName: "arrow.triangle.swap")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .help("Has fallback pool")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
    }
}

// MARK: - Profile Detail View

struct ProfileDetailView: View {
    let profile: MinerProfileTemplate
    let onDeploy: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var showDeleteConfirmation: Bool = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(profile.name)
                                .font(.system(size: 20, weight: .semibold))
                            
                            Text("Mining Profile")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        HStack(spacing: 8) {
                            Button(action: onDeploy) {
                                Label("Deploy", systemImage: "arrow.right.circle")
                            }
                            .buttonStyle(.borderedProminent)
                            
                            Menu {
                                Button(action: onEdit) {
                                    Label("Edit Profile", systemImage: "pencil")
                                }
                                Divider()
                                Button(role: .destructive, action: { showDeleteConfirmation = true }) {
                                    Label("Delete Profile", systemImage: "trash")
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                                    .font(.system(size: 16))
                            }
                            .menuStyle(.borderlessButton)
                            .frame(width: 32)
                        }
                    }
                }
                .padding(20)
                
                Divider()
                
                // Primary Pool Configuration
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "Primary Pool", icon: "server.rack")
                    
                    if !profile.stratumURL.isEmpty {
                        DetailRow(label: "Stratum URL", value: profile.stratumURL)
                        DetailRow(label: "Port", value: "\(profile.stratumPort)")
                        
                        if !profile.poolAccount.isEmpty {
                            DetailRow(label: "Account", value: profile.poolAccount)
                        }
                        
                        if !profile.stratumPassword.isEmpty {
                            DetailRow(label: "Password", value: "••••••••")
                        }
                        
                        if profile.isPrimaryPoolParasite, let lightningAddr = profile.parasiteLightningAddress, !lightningAddr.isEmpty {
                            DetailRow(label: "Lightning", value: lightningAddr)
                        }
                    } else {
                        Text("No pool configured")
                            .font(.system(size: 13))
                            .foregroundStyle(.tertiary)
                            .padding(.vertical, 8)
                    }
                }
                .padding(20)
                
                // Fallback Pool Configuration
                if let fallbackURL = profile.fallbackStratumURL, !fallbackURL.isEmpty {
                    Divider()
                        .padding(.horizontal, 20)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Fallback Pool", icon: "arrow.triangle.swap")
                        
                        DetailRow(label: "Stratum URL", value: fallbackURL)
                        
                        if let port = profile.fallbackStratumPort {
                            DetailRow(label: "Port", value: "\(port)")
                        }
                        
                        if let account = profile.fallbackStratumAccount, !account.isEmpty {
                            DetailRow(label: "Account", value: account)
                        }
                        
                        if profile.isFallbackPoolParasite, let lightningAddr = profile.fallbackParasiteLightningAddress, !lightningAddr.isEmpty {
                            DetailRow(label: "Lightning", value: lightningAddr)
                        }
                    }
                    .padding(20)
                }
                
                Divider()
                    .padding(.horizontal, 20)
                
                // Notes
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "Notes", icon: "note.text")
                    
                    if !profile.templateNotes.isEmpty {
                        Text(profile.templateNotes)
                            .font(.system(size: 13))
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                    } else {
                        Text("No notes")
                            .font(.system(size: 13))
                            .foregroundStyle(.tertiary)
                            .padding(.vertical, 8)
                    }
                }
                .padding(20)
            }
        }
        .alert("Delete Profile?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive, action: onDelete)
        } message: {
            Text("This action cannot be undone.")
        }
    }
}

// MARK: - Helper Views

private struct SectionHeader: View {
    let title: String
    let icon: String
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }
}

private struct DetailRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
        }
        .padding(.vertical, 4)
    }
}
