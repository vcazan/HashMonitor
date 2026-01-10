//
//  FirmwareReleasesView.swift
//  HashRipper
//
//  Created by Matt Sellars
//

import Combine
import SwiftData
import SwiftUI

struct FirmwareReleasesView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.firmwareReleaseViewModel) private var viewModel: FirmwareReleasesViewModel
    @Environment(\.firmwareDownloadsManager) private var downloadsManager: FirmwareDownloadsManager!

    @State private var selectedRelease: FirmwareRelease?
    @State private var allReleases: [FirmwareRelease] = []
    @State private var stableReleases: [FirmwareRelease] = []
    @State private var searchText: String = ""
    @State private var selectedDeviceFilter: String = "All"
    
    private var releases: [FirmwareRelease] {
        if viewModel.showPreReleases {
            return stableReleases
        } else {
            return stableReleases.filter { !$0.isPreRelease }
        }
    }

    private var deviceTypes: [String] {
        let types = Set(releases.map { $0.device })
        return ["All"] + types.sorted()
    }
    
    private var filteredReleases: [FirmwareRelease] {
        var result = releases
        
        // Filter by device type
        if selectedDeviceFilter != "All" {
            result = result.filter { $0.device == selectedDeviceFilter }
        }
        
        // Filter by search
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter { release in
                release.name.lowercased().contains(query) ||
                release.versionTag.lowercased().contains(query) ||
                release.device.lowercased().contains(query)
                                }
                        }
        
        return result
    }

    var body: some View {
        HSplitView {
            // Left: Release List
            releaseListPanel
                .frame(minWidth: 300, idealWidth: 360, maxWidth: 450)
            
            // Right: Detail View
            detailPanel
                .frame(minWidth: 500)
        }
        .onAppear {
            loadReleases()
        }
        .task {
            viewModel.updateReleasesSources()
        }
    }
    
    // MARK: - Release List Panel
    
    private var releaseListPanel: some View {
        VStack(spacing: 0) {
            // Header
            HStack(alignment: .center) {
                Text("Releases")
                    .font(.system(size: 13, weight: .semibold))
                
                Spacer()
                
                Text("\(filteredReleases.count)")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(Capsule())
                
                // Pre-release toggle
                Toggle(isOn: viewModel.includePreReleases) {
                    Image(systemName: "flask")
                        .font(.system(size: 11))
                }
                .toggleStyle(.button)
                .buttonStyle(.plain)
                .foregroundStyle(viewModel.showPreReleases ? .orange : .secondary)
                .help(viewModel.showPreReleases ? "Hide pre-releases" : "Show pre-releases")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            
            // Search and filter
            VStack(spacing: 8) {
                // Search field
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    
                    TextField("Search firmware...", text: $searchText)
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
                
                // Device type filter
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(deviceTypes, id: \.self) { device in
                            FilterChip(
                                label: device,
                                isSelected: selectedDeviceFilter == device
                            ) {
                                withAnimation(.easeOut(duration: 0.15)) {
                                    selectedDeviceFilter = device
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
            
            Divider()
            
            // Release list
            if filteredReleases.isEmpty {
                emptyListState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredReleases) { release in
                            ReleaseListRow(
                                release: release,
                                isSelected: selectedRelease?.id == release.id,
                                isDownloaded: isReleaseDownloaded(release)
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation(.easeOut(duration: 0.12)) {
                                    selectedRelease = release
                                }
                            }
                            
                            if release.id != filteredReleases.last?.id {
                                Divider()
                                    .padding(.leading, 60)
                            }
                        }
                    }
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
    
    private var emptyListState: some View {
        VStack(spacing: 12) {
            if stableReleases.isEmpty {
                ProgressView()
                    .scaleEffect(0.8)
                Text("Loading firmware...")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 24, weight: .thin))
                    .foregroundStyle(.quaternary)
                Text("No firmware found")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Text("Try a different search or filter")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 40)
    }
    
    // MARK: - Detail Panel
    
    private var detailPanel: some View {
        Group {
            if let release = selectedRelease {
                FirmwareDetailView(release: release)
            } else {
                emptyDetailView
            }
        }
        .background(colorScheme == .dark ? Color(white: 0.08) : Color(white: 0.98))
    }
    
    private var emptyDetailView: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 48, weight: .ultraLight))
                .foregroundStyle(.quaternary)
            
            VStack(spacing: 4) {
                Text("Select Firmware")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                
                Text("Choose a firmware release to view details")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Helpers
    
    private func isReleaseDownloaded(_ release: FirmwareRelease) -> Bool {
        let minerCompleted = downloadsManager.isDownloaded(release: release, fileType: .miner)
        let wwwCompleted = downloadsManager.isDownloaded(release: release, fileType: .www)
        return minerCompleted && wwwCompleted
    }
    
    private func loadReleases() {
        let container = modelContext.container
        let currentReleaseIds = allReleases.map(\.id)

        Task.detached {
            let backgroundContext = ModelContext(container)
            let descriptor = FetchDescriptor<FirmwareRelease>(
                sortBy: [SortDescriptor(\.releaseDate, order: .reverse)]
            )

            do {
                let fetchedReleases = try backgroundContext.fetch(descriptor)
                let newReleaseIds = fetchedReleases.map(\.id)

                if newReleaseIds != currentReleaseIds {
                    await MainActor.run {
                        do {
                            let mainReleases = try modelContext.fetch(descriptor)
                            EnsureUISafe {
                                allReleases = mainReleases
                                updateStableReleases()
                            }
                        } catch {
                            print("Error loading firmware releases: \(error)")
                        }
                    }
                }
            } catch {
                print("Error loading firmware releases in background: \(error)")
            }
        }
    }

    private func updateStableReleases() {
        let newReleaseIds = Set(allReleases.map(\.id))
        let currentReleaseIds = Set(stableReleases.map(\.id))

        if newReleaseIds != currentReleaseIds {
            stableReleases = allReleases
        }
    }
}

// MARK: - Filter Chip

private struct FilterChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? .white : .secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isSelected ? Color.accentColor : (colorScheme == .dark ? Color(white: 0.15) : Color(white: 0.92)))
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Release List Row

private struct ReleaseListRow: View {
    let release: FirmwareRelease
    let isSelected: Bool
    let isDownloaded: Bool
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon
            ZStack {
                Image(systemName: isDownloaded ? "checkmark.circle.fill" : "arrow.down.circle")
                    .font(.system(size: 18))
                    .foregroundStyle(isDownloaded ? .green : .secondary)
    }
            .frame(width: 32, height: 32)
            .background(isDownloaded ? Color.green.opacity(0.12) : Color.secondary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            
            // Info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(release.name)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    
                    if release.isPreRelease {
                        Text("PRE")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.orange.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                }
                
                HStack(spacing: 8) {
                    Text(release.device)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    
                    Text("•")
                        .foregroundStyle(.quaternary)
                    
                    Text(dateFormatter.string(from: release.releaseDate))
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
}
            }
            
            Spacer()
            
            // Download status
            if isDownloaded {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.green)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
    }
}

// MARK: - Firmware Detail View

private struct FirmwareDetailView: View {
    let release: FirmwareRelease
    
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.firmwareDownloadsManager) private var downloadsManager: FirmwareDownloadsManager!
    @State private var showingDeploymentWizard = false
    @State private var settings = AppSettings.shared
    
    private var isDownloaded: Bool {
        downloadsManager.isDownloaded(release: release, fileType: .miner) &&
        downloadsManager.isDownloaded(release: release, fileType: .www)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Text(release.name)
                                    .font(.system(size: 20, weight: .semibold))
                                
                                if release.isPreRelease {
                        Text("Pre-release")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(.orange)
                            .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(Color.orange.opacity(0.15))
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                }
                            }
                            
                            HStack(spacing: 12) {
                                Label(release.device, systemImage: "cpu")
                                Label(dateFormatter.string(from: release.releaseDate), systemImage: "calendar")
                            }
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        // Actions
                        if isDownloaded {
                            HStack(spacing: 8) {
                                Button {
                                    showingDeploymentWizard = true
                                } label: {
                                    Label("Deploy", systemImage: "arrow.right.circle")
                                }
                                .buttonStyle(.borderedProminent)
                                
                                Menu {
                                    Button {
                                        downloadsManager.showFirmwareDirectoryInFinder(release: release)
                                    } label: {
                                        Label("Show in Finder", systemImage: "folder")
                                    }
                                    Divider()
                                    Button(role: .destructive) {
                                        try? downloadsManager.deleteDownloadedFiles(for: release)
                                    } label: {
                                        Label("Delete Files", systemImage: "trash")
                                    }
                                } label: {
                                    Image(systemName: "ellipsis.circle")
                                        .font(.system(size: 16))
                                }
                                .menuStyle(.borderlessButton)
                                .frame(width: 32)
                            }
                        } else {
                            FirmwareDownloadButton(firmwareRelease: release, style: .prominent)
                        }
                    }
                }
                .padding(20)
                
                Divider()
                
                // File Info
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "Files", icon: "doc.zipper")
                    
                    FileInfoRow(
                        filename: release.firmwareFilename,
                        size: release.minerBinFileSize,
                        isDownloaded: downloadsManager.isDownloaded(release: release, fileType: .miner),
                        type: "Firmware"
                    )
                    
                    FileInfoRow(
                        filename: release.wwwFilename,
                        size: release.wwwBinFileSize,
                        isDownloaded: downloadsManager.isDownloaded(release: release, fileType: .www),
                        type: "Web UI"
                    )
            }
                .padding(20)
                
                Divider()
                    .padding(.horizontal, 20)
                
                // Release Notes
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "Release Notes", icon: "doc.text")
                    
                    if !release.changeLogMarkup.isEmpty {
                        Text(release.changeLogMarkup)
                            .font(.system(size: 13))
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text("No release notes available")
                            .font(.system(size: 13))
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(20)
            }
        }
        .sheet(isPresented: $showingDeploymentWizard) {
            if settings.usePersistentDeployments {
                NewDeploymentWizard(firmwareRelease: release)
            } else {
                FirmwareDeploymentWizard(firmwareRelease: release)
            }
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

private struct FileInfoRow: View {
    let filename: String
    let size: Int
    let isDownloaded: Bool
    let type: String
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isDownloaded ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 14))
                .foregroundStyle(isDownloaded ? Color.green : Color.secondary.opacity(0.5))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(filename)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .lineLimit(1)
                
                Text("\(type) • \(formatFileSize(size))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
                }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(colorScheme == .dark ? Color(white: 0.12) : Color(white: 0.96))
        )
                    }
}

let dateFormatter: DateFormatter = {
    let df = DateFormatter()
    df.dateStyle = .medium
    return df
}()

func formatFileSize(_ sizeInBytes: Int) -> String {
    let formatter = ByteCountFormatter()
    formatter.allowedUnits = [.useKB, .useMB]
    formatter.countStyle = .file
    return formatter.string(fromByteCount: Int64(sizeInBytes))
}
