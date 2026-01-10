//
//  HashOpsView.swift
//  HashRipper
//
//  Created by Matt Sellars
//

import SwiftData
import SwiftUI

struct HashOpsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme

    @State private var selectedMiner: Miner? = nil
    @State private var miners: [Miner] = []
    @State private var debounceTask: Task<Void, Never>?
    @State private var searchText: String = ""
    
    private var filteredMiners: [Miner] {
        if searchText.isEmpty {
            return miners
        }
        let query = searchText.lowercased()
        return miners.filter { miner in
            miner.hostName.lowercased().contains(query) ||
            miner.minerDeviceDisplayName.lowercased().contains(query) ||
            miner.ipAddress.lowercased().contains(query)
        }
    }

    var body: some View {
        HSplitView {
            // Left: Miner List
            minerListPanel
                .frame(minWidth: 280, idealWidth: 320, maxWidth: 400)
            
            // Right: Detail View
            detailPanel
                .frame(minWidth: 500)
        }
        .onAppear {
            loadMiners()
        }
        .onReceive(NotificationCenter.default.publisher(for: .minerUpdateInserted)) { _ in
            debounceTask?.cancel()
            debounceTask = Task {
                try? await Task.sleep(nanoseconds: 500_000_000)
                if !Task.isCancelled {
                    loadMiners()
                }
            }
        }
        .onDisappear {
            debounceTask?.cancel()
        }
    }
    
    // MARK: - Miner List Panel
    
    private var minerListPanel: some View {
        VStack(spacing: 0) {
            // List header
            HStack(alignment: .center) {
                Text("Miners")
                    .font(.system(size: 13, weight: .semibold))
                
                Spacer()
                
                Text("\(filteredMiners.count)")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            
            // Search field
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                
                TextField("Search miners...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(colorScheme == .dark ? Color(white: 0.12) : Color(white: 0.95))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
            
            Divider()
            
            // Miner list
            if filteredMiners.isEmpty && !searchText.isEmpty {
                // No results state
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 24, weight: .thin))
                        .foregroundStyle(.quaternary)
                    Text("No miners found")
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
                        ForEach(filteredMiners) { miner in
                            MinerListRow(
                                miner: miner,
                                isSelected: selectedMiner?.macAddress == miner.macAddress
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation(.easeOut(duration: 0.12)) {
                                    selectedMiner = miner
                                }
                            }
                            
                            if miner.id != filteredMiners.last?.id {
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
    
    // MARK: - Detail Panel
    
    private var detailPanel: some View {
        Group {
            if let miner = selectedMiner {
                MinerDetailView(miner: miner)
            } else {
                emptyStateView
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "cpu")
                .font(.system(size: 40, weight: .thin))
                .foregroundStyle(.quaternary)
            
            Text("Select a miner")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
            
            Text("Choose from the list to view details")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func loadMiners() {
        let container = modelContext.container
        let currentMinerIds = miners.map(\.macAddress)

        Task.detached {
            let backgroundContext = ModelContext(container)
            let descriptor = FetchDescriptor<Miner>(
                sortBy: [SortDescriptor(\.hostName)]
            )

            do {
                let fetchedMiners = try backgroundContext.fetch(descriptor)
                let newMinerIds = fetchedMiners.map(\.macAddress)

                if newMinerIds != currentMinerIds {
                    await MainActor.run {
                        do {
                            let mainMiners = try modelContext.fetch(descriptor)
                            EnsureUISafe {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    miners = mainMiners
                                    
                                    // Auto-select first miner if none selected
                                    if selectedMiner == nil && !miners.isEmpty {
                                        selectedMiner = miners.first
                                    }
                                }
                            }
                        } catch {
                            print("Error loading miners on main thread: \(error)")
                        }
                    }
                }
            } catch {
                print("Error loading miners in background: \(error)")
            }
        }
    }
}

// MARK: - Miner List Row

private struct MinerListRow: View {
    let miner: Miner
    let isSelected: Bool
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @State private var latestUpdate: MinerUpdate?
    
    private var rowBackground: Color {
        if isSelected {
            return colorScheme == .dark 
                ? Color.blue.opacity(0.2)
                : Color.blue.opacity(0.08)
        }
        return .clear
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Miner icon
            Image.icon(forMinerType: miner.minerType)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 32, height: 32)
            
            // Info
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(miner.hostName)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    
                    // Status dot
                    Circle()
                        .fill(miner.isOffline ? Color.red : Color.green)
                        .frame(width: 6, height: 6)
                }
                
                Text(miner.minerDeviceDisplayName)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            
            Spacer(minLength: 8)
            
            // Hash rate
            VStack(alignment: .trailing, spacing: 2) {
                if let update = latestUpdate {
                    let formatted = formatMinerHashRate(rawRateValue: update.hashRate)
                    Text(formatted.rateString)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(miner.isOffline ? .secondary : .primary)
                    Text(formatted.rateSuffix)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                } else {
                    Text("—")
                        .font(.system(size: 14))
                        .foregroundStyle(.quaternary)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(rowBackground)
        .overlay(
            Rectangle()
                .fill(isSelected ? Color.blue : Color.clear)
                .frame(width: 3),
            alignment: .leading
        )
        .onAppear { loadUpdate() }
        .onReceive(NotificationCenter.default.publisher(for: .minerUpdateInserted)) { notification in
            if let macAddress = notification.userInfo?["macAddress"] as? String,
               macAddress == miner.macAddress {
                loadUpdate()
            }
        }
    }
    
    private func loadUpdate() {
        let macAddress = miner.macAddress
        var descriptor = FetchDescriptor<MinerUpdate>(
            predicate: #Predicate<MinerUpdate> { $0.macAddress == macAddress },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        latestUpdate = try? modelContext.fetch(descriptor).first
    }
}

let backgroundGradient = LinearGradient(
    colors: [.orange, .blue],
    startPoint: .top, endPoint: .bottom)
