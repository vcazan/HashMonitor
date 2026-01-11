//
//  MinerLogsSheet.swift
//  HashRipper-iOS
//
//  Real-time logs from miner via WebSocket
//

import SwiftUI
import Combine
import HashRipperKit
import AxeOSClient

struct MinerLogsSheet: View {
    let miner: Miner
    
    @Environment(\.dismiss) private var dismiss
    
    @StateObject private var viewModel: LogsViewModel
    
    init(miner: Miner) {
        self.miner = miner
        self._viewModel = StateObject(wrappedValue: LogsViewModel(miner: miner))
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Filter bar
                filterBar
                
                Divider()
                
                // Log entries
                if viewModel.entries.isEmpty {
                    emptyStateView
                } else {
                    logEntriesView
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Logs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 12) {
                        Button {
                            viewModel.clearLogs()
                        } label: {
                            Image(systemName: "trash")
                        }
                        .disabled(viewModel.entries.isEmpty)
                        
                        Button {
                            viewModel.toggleConnection()
                        } label: {
                            Image(systemName: viewModel.isConnected ? "pause.fill" : "play.fill")
                        }
                    }
                }
            }
            .onAppear {
                viewModel.connect()
            }
            .onDisappear {
                viewModel.disconnect()
            }
        }
    }
    
    // MARK: - Filter Bar
    
    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Connection status
                HStack(spacing: 6) {
                    Circle()
                        .fill(viewModel.isConnected ? AppColors.success : AppColors.error)
                        .frame(width: 8, height: 8)
                    Text(viewModel.isConnected ? "Live" : "Disconnected")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(viewModel.isConnected ? AppColors.success : AppColors.error)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(.tertiarySystemFill))
                .clipShape(Capsule())
                
                Divider()
                    .frame(height: 20)
                
                // Level filters
                ForEach(LogLevel.allCases, id: \.self) { level in
                    LevelFilterButton(
                        level: level,
                        isSelected: viewModel.selectedLevels.contains(level)
                    ) {
                        viewModel.toggleLevel(level)
                    }
                }
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(AppColors.cardBackground)
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()
            
            Image(systemName: "terminal")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(AppColors.mutedText)
            
            VStack(spacing: 4) {
                Text(viewModel.isConnected ? "Waiting for logs..." : "Not Connected")
                    .font(.system(size: 16, weight: .medium))
                
                Text(viewModel.isConnected ? "Logs will appear as they're generated" : "Tap play to connect")
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.subtleText)
            }
            
            if viewModel.isConnected {
                ProgressView()
                    .padding(.top, 8)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Log Entries
    
    private var logEntriesView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(viewModel.filteredEntries) { entry in
                        LogEntryRow(entry: entry)
                            .id(entry.id)
                    }
                }
                .padding(.vertical, 4)
            }
            .onChange(of: viewModel.filteredEntries.count) { _, _ in
                if viewModel.autoScroll, let lastEntry = viewModel.filteredEntries.last {
                    withAnimation(.easeOut(duration: 0.1)) {
                        proxy.scrollTo(lastEntry.id, anchor: .bottom)
                    }
                }
            }
        }
    }
}

// MARK: - Log Level

enum LogLevel: String, CaseIterable {
    case info = "I"
    case warning = "W"
    case error = "E"
    case debug = "D"
    
    var displayName: String {
        switch self {
        case .info: return "Info"
        case .warning: return "Warn"
        case .error: return "Error"
        case .debug: return "Debug"
        }
    }
    
    var color: Color {
        switch self {
        case .info: return AppColors.hashRate
        case .warning: return AppColors.warning
        case .error: return AppColors.error
        case .debug: return AppColors.subtleText
        }
    }
}

// MARK: - Log Entry

struct LogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let level: LogLevel
    let component: String
    let message: String
}

// MARK: - Level Filter Button

struct LevelFilterButton: View {
    let level: LogLevel
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(level.displayName)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(isSelected ? level.color.opacity(0.2) : Color(.tertiarySystemFill))
                .foregroundStyle(isSelected ? level.color : AppColors.subtleText)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Log Entry Row

struct LogEntryRow: View {
    let entry: LogEntry
    
    private var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: entry.timestamp)
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(timeString)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(AppColors.mutedText)
                .frame(width: 70, alignment: .leading)
            
            Text(entry.level.rawValue)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(entry.level.color)
                .frame(width: 14)
            
            Text(entry.component)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(AppColors.subtleText)
                .frame(width: 50, alignment: .leading)
                .lineLimit(1)
            
            Text(entry.message)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(3)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }
}

// MARK: - View Model

@MainActor
class LogsViewModel: ObservableObject {
    @Published var entries: [LogEntry] = []
    @Published var isConnected = false
    @Published var autoScroll = true
    @Published var selectedLevels: Set<LogLevel> = Set(LogLevel.allCases)
    @Published var searchText = ""
    
    private let miner: Miner
    private var websocket: AxeOSWebsocketClient?
    private var cancellables = Set<AnyCancellable>()
    private var connectionTask: Task<Void, Never>?
    
    var filteredEntries: [LogEntry] {
        entries.filter { entry in
            guard selectedLevels.contains(entry.level) else { return false }
            
            if !searchText.isEmpty {
                let query = searchText.lowercased()
                return entry.message.lowercased().contains(query) ||
                       entry.component.lowercased().contains(query)
            }
            return true
        }
    }
    
    init(miner: Miner) {
        self.miner = miner
    }
    
    func connect() {
        let client = AxeOSWebsocketClient()
        websocket = client
        
        let ipAddress = miner.ipAddress
        
        // Connect and subscribe in a Task since the client is an actor
        connectionTask = Task { [weak self] in
            guard let self = self else { return }
            guard let url = URL(string: "ws://\(ipAddress)/api/ws") else { return }
            
            // Subscribe to messages
            let messagePublisher = await client.messagePublisher
            messagePublisher
                .receive(on: DispatchQueue.main)
                .sink { [weak self] message in
                    self?.parseLogMessage(message)
                }
                .store(in: &self.cancellables)
            
            // Subscribe to connection state
            let statePublisher = await client.connectionStatePublisher
            statePublisher
                .receive(on: DispatchQueue.main)
                .sink { [weak self] state in
                    self?.isConnected = (state == .connected)
                }
                .store(in: &self.cancellables)
            
            // Enable auto-reconnect and connect
            await client.setAutoReconnect(true, maxAttempts: 5)
            await client.connect(to: url)
        }
    }
    
    func disconnect() {
        connectionTask?.cancel()
        connectionTask = nil
        
        Task {
            await websocket?.close()
        }
        
        websocket = nil
        isConnected = false
        cancellables.removeAll()
    }
    
    func toggleConnection() {
        if isConnected {
            disconnect()
        } else {
            connect()
        }
    }
    
    func clearLogs() {
        entries.removeAll()
    }
    
    func toggleLevel(_ level: LogLevel) {
        if selectedLevels.contains(level) {
            selectedLevels.remove(level)
        } else {
            selectedLevels.insert(level)
        }
    }
    
    private func parseLogMessage(_ message: String) {
        // Parse log format: [timestamp] [level] [component]: message
        // Example: [123456789] I SYSTEM: Boot complete
        
        let lines = message.components(separatedBy: "\n")
        
        for line in lines {
            guard !line.isEmpty else { continue }
            
            // Try to parse structured log
            let level: LogLevel
            var component = "SYSTEM"
            var msg = line
            
            if line.contains(" I ") {
                level = .info
            } else if line.contains(" W ") {
                level = .warning
            } else if line.contains(" E ") {
                level = .error
            } else if line.contains(" D ") {
                level = .debug
            } else {
                level = .info
            }
            
            // Try to extract component and message
            if let colonIndex = line.firstIndex(of: ":") {
                let beforeColon = String(line[..<colonIndex])
                if let lastSpace = beforeColon.lastIndex(of: " ") {
                    component = String(beforeColon[beforeColon.index(after: lastSpace)...])
                }
                let afterColonIndex = line.index(after: colonIndex)
                if afterColonIndex < line.endIndex {
                    msg = String(line[afterColonIndex...]).trimmingCharacters(in: .whitespaces)
                }
            }
            
            let entry = LogEntry(
                timestamp: Date(),
                level: level,
                component: component,
                message: msg
            )
            
            entries.append(entry)
            
            // Keep only last 500 entries
            if entries.count > 500 {
                entries.removeFirst(entries.count - 500)
            }
        }
    }
}

#Preview {
    MinerLogsSheet(miner: Miner(
        hostName: "test-miner",
        ipAddress: "192.168.1.100",
        ASICModel: "BM1366",
        macAddress: "AA:BB:CC:DD:EE:FF"
    ))
}
