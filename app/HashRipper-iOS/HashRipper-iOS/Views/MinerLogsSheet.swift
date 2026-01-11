//
//  MinerLogsSheet.swift
//  HashMonitor
//
//  Apple Design Language - Console app inspired
//

import SwiftUI
import Combine
import HashRipperKit
import AxeOSClient

// MARK: - Log Entry Model

struct LogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let level: LogLevel
    let component: String
    let message: String
    
    enum LogLevel: String, CaseIterable {
        case debug = "D"
        case info = "I"
        case warning = "W"
        case error = "E"
        
        var color: Color {
            switch self {
            case .debug: return AppColors.textTertiary
            case .info: return AppColors.efficiency
            case .warning: return AppColors.statusWarning
            case .error: return AppColors.statusOffline
            }
        }
        
        var displayName: String {
            switch self {
            case .debug: return "Debug"
            case .info: return "Info"
            case .warning: return "Warning"
            case .error: return "Error"
            }
        }
    }
}

// MARK: - View Model

@MainActor
class MinerLogsViewModel: ObservableObject {
    @Published var entries: [LogEntry] = []
    @Published var isConnected = false
    @Published var autoScroll = true
    @Published var searchText = ""
    @Published var selectedLevels: Set<LogEntry.LogLevel> = Set(LogEntry.LogLevel.allCases)
    
    private let ipAddress: String
    private let websocketClient: AxeOSWebsocketClient
    private var cancellables = Set<AnyCancellable>()
    
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
        self.ipAddress = miner.ipAddress
        self.websocketClient = AxeOSWebsocketClient()
        
        setupSubscriptions()
    }
    
    private func setupSubscriptions() {
        Task {
            await websocketClient.setAutoReconnect(true, maxAttempts: 10)
            
            // Subscribe to messages
            let messagePublisher = await websocketClient.messagePublisher
            messagePublisher
                .receive(on: DispatchQueue.main)
                .sink { [weak self] message in
                    self?.parseLogMessage(message)
                }
                .store(in: &cancellables)
            
            // Subscribe to connection state
            let connectionPublisher = await websocketClient.connectionStatePublisher
            connectionPublisher
                .receive(on: DispatchQueue.main)
                .sink { [weak self] state in
                    self?.isConnected = (state == .connected)
                }
                .store(in: &cancellables)
        }
    }
    
    private func parseLogMessage(_ message: String) {
        // Parse log format: [LEVEL] [TIMESTAMP] [COMPONENT] MESSAGE
        // Example: I (12345) wifi: connected
        
        let level: LogEntry.LogLevel
        let component: String
        let cleanMessage: String
        
        if message.hasPrefix("I ") {
            level = .info
        } else if message.hasPrefix("W ") {
            level = .warning
        } else if message.hasPrefix("E ") {
            level = .error
        } else if message.hasPrefix("D ") {
            level = .debug
        } else {
            level = .info
        }
        
        // Extract component
        if let colonIndex = message.firstIndex(of: ":") {
            let beforeColon = message[..<colonIndex]
            if let parenEnd = beforeColon.lastIndex(of: ")") {
                let startIndex = message.index(after: parenEnd)
                component = String(message[startIndex..<colonIndex]).trimmingCharacters(in: .whitespaces)
            } else {
                component = "System"
            }
            cleanMessage = String(message[message.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
        } else {
            component = "System"
            cleanMessage = message
        }
        
        let entry = LogEntry(
            timestamp: Date(),
            level: level,
            component: component,
            message: cleanMessage
        )
        
        entries.append(entry)
        
        // Keep only last 500 entries
        if entries.count > 500 {
            entries.removeFirst(entries.count - 500)
        }
    }
    
    func connect() {
        guard let url = URL(string: "ws://\(ipAddress)/ws") else { return }
        Task {
            await websocketClient.connect(to: url)
        }
    }
    
    func disconnect() {
        Task {
            await websocketClient.close()
        }
    }
    
    func clearLogs() {
        entries.removeAll()
    }
    
    func toggleLevel(_ level: LogEntry.LogLevel) {
        if selectedLevels.contains(level) {
            selectedLevels.remove(level)
        } else {
            selectedLevels.insert(level)
        }
    }
}

// MARK: - Main View

struct MinerLogsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: MinerLogsViewModel
    
    init(miner: Miner) {
        _viewModel = StateObject(wrappedValue: MinerLogsViewModel(miner: miner))
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Dark console background
                Color.black
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Filters bar
                    filtersBar
                        .padding(.horizontal)
                        .padding(.vertical, Spacing.sm)
                    
                    Divider()
                        .background(Color.white.opacity(0.1))
                    
                    // Log entries
                    logEntriesView
                }
            }
            .navigationTitle("Logs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .tint(.white)
                }
                
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: Spacing.md) {
                        // Auto scroll toggle
                        Button {
                            Haptics.selection()
                            viewModel.autoScroll.toggle()
                        } label: {
                            Image(systemName: viewModel.autoScroll ? "arrow.down.to.line" : "arrow.down.to.line.compact")
                                .foregroundStyle(viewModel.autoScroll ? .teal : .gray)
                        }
                        
                        // Clear button
                        Button {
                            Haptics.impact(.light)
                            viewModel.clearLogs()
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(.white.opacity(0.7))
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
    
    // MARK: - Filters Bar
    
    private var filtersBar: some View {
        HStack(spacing: Spacing.md) {
            // Connection status
            HStack(spacing: Spacing.xs) {
                Circle()
                    .fill(viewModel.isConnected ? AppColors.statusOnline : AppColors.statusOffline)
                    .frame(width: 6, height: 6)
                
                Text(viewModel.isConnected ? "Connected" : "Disconnected")
                    .font(.captionMedium)
                    .foregroundStyle(.white.opacity(0.6))
            }
            
            Spacer()
            
            // Level filters
            HStack(spacing: Spacing.xs) {
                ForEach(LogEntry.LogLevel.allCases, id: \.self) { level in
                    Button {
                        Haptics.selection()
                        viewModel.toggleLevel(level)
                    } label: {
                        Text(level.rawValue)
                            .font(.captionLarge)
                            .fontWeight(.semibold)
                            .fontDesign(.monospaced)
                            .foregroundStyle(viewModel.selectedLevels.contains(level) ? level.color : .gray)
                            .padding(.horizontal, Spacing.sm)
                            .padding(.vertical, Spacing.xs)
                            .background(
                                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                                    .fill(viewModel.selectedLevels.contains(level) ? level.color.opacity(0.2) : Color.white.opacity(0.05))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    
    // MARK: - Log Entries View
    
    private var logEntriesView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if viewModel.entries.isEmpty {
                        emptyState
                    } else {
                        ForEach(viewModel.filteredEntries) { entry in
                            LogEntryRow(entry: entry)
                                .id(entry.id)
                        }
                    }
                }
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)
            }
            .onChange(of: viewModel.filteredEntries.count) { _, _ in
                if viewModel.autoScroll, let lastEntry = viewModel.filteredEntries.last {
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(lastEntry.id, anchor: .bottom)
                    }
                }
            }
        }
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "terminal")
                .font(.system(size: 40))
                .foregroundStyle(.white.opacity(0.3))
            
            Text("Waiting for logs...")
                .font(.bodyMedium)
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 80)
    }
}

// MARK: - Log Entry Row

struct LogEntryRow: View {
    let entry: LogEntry
    
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()
    
    var body: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            // Level badge
            Text(entry.level.rawValue)
                .font(.monoSmall)
                .fontWeight(.bold)
                .foregroundStyle(entry.level.color)
                .frame(width: 14)
            
            // Timestamp
            Text(Self.timeFormatter.string(from: entry.timestamp))
                .font(.monoSmall)
                .foregroundStyle(.white.opacity(0.4))
            
            // Component
            Text(entry.component)
                .font(.monoSmall)
                .foregroundStyle(.cyan.opacity(0.8))
                .frame(minWidth: 60, alignment: .leading)
            
            // Message
            Text(entry.message)
                .font(.monoSmall)
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(nil)
                .textSelection(.enabled)
        }
        .padding(.vertical, Spacing.xxs)
    }
}

// MARK: - Preview

#Preview {
    MinerLogsSheet(miner: Miner(
        hostName: "BitAxe",
        ipAddress: "192.168.1.100",
        ASICModel: "BM1366",
        macAddress: "AA:BB:CC:DD:EE:FF"
    ))
}
