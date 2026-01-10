//
//  MinerLogsDrawerView.swift
//  HashRipper
//
//  AWS Console-style logs drawer for real-time miner logs
//

import SwiftUI
import Combine

struct MinerLogsDrawerView: View {
    let miner: Miner
    @Binding var isExpanded: Bool
    
    @Environment(\.colorScheme) private var colorScheme
    
    @StateObject private var viewModel: LogsDrawerViewModel
    
    init(miner: Miner, isExpanded: Binding<Bool>) {
        self.miner = miner
        self._isExpanded = isExpanded
        self._viewModel = StateObject(wrappedValue: LogsDrawerViewModel(miner: miner))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header bar (always visible)
            headerBar
            
            // Expandable content
            if isExpanded {
                VStack(spacing: 0) {
                    // Filters
                    filtersBar
                    
                    Divider()
                    
                    // Log entries
                    logEntriesView
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(colorScheme == .dark ? Color(white: 0.08) : Color(white: 0.96))
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isExpanded)
        .onChange(of: isExpanded) { _, newValue in
            if newValue {
                // Setup session only when drawer is first expanded
                viewModel.setupSessionIfNeeded()
                
                if !viewModel.isRecording {
                    // Auto-start recording when drawer is expanded
                    viewModel.toggleRecording()
                }
            }
        }
    }
    
    // MARK: - Header Bar
    
    private var headerBar: some View {
        HStack(spacing: 12) {
            // Toggle button
            Button(action: { isExpanded.toggle() }) {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    
                    Image(systemName: "terminal")
                        .font(.system(size: 12, weight: .medium))
                    
                    Text("Logs")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
            
            // Connection status (only show when recording)
            if viewModel.isRecording {
                HStack(spacing: 4) {
                    Circle()
                        .fill(viewModel.isConnected ? Color.green : Color.orange)
                        .frame(width: 6, height: 6)
                    Text(viewModel.isConnected ? "Connected" : "Connecting...")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            
            // Entry count
            if !viewModel.filteredEntries.isEmpty {
                Text("\(viewModel.filteredEntries.count) entries")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(Capsule())
            }
            
            Spacer()
            
            if isExpanded {
                // Clear button
                Button(action: { viewModel.clearLogs() }) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear logs")
                
                // Auto-scroll toggle
                Button(action: { viewModel.autoScroll.toggle() }) {
                    Image(systemName: viewModel.autoScroll ? "arrow.down.to.line" : "arrow.down.to.line.compact")
                        .font(.system(size: 11))
                        .foregroundStyle(viewModel.autoScroll ? .blue : .secondary)
                }
                .buttonStyle(.plain)
                .help(viewModel.autoScroll ? "Auto-scroll enabled" : "Auto-scroll disabled")
                
                // Start/Stop recording
                Button(action: { viewModel.toggleRecording() }) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(viewModel.isRecording ? Color.red : Color.gray)
                            .frame(width: 8, height: 8)
                        Text(viewModel.isRecording ? "Stop" : "Start")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(viewModel.isRecording ? Color.red.opacity(0.15) : Color.secondary.opacity(0.1))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(colorScheme == .dark ? Color(white: 0.1) : Color(white: 0.94))
        .overlay(Divider(), alignment: .top)
    }
    
    // MARK: - Filters Bar
    
    private var filtersBar: some View {
        HStack(spacing: 12) {
            // Search
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                
                TextField("Filter logs...", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                
                if !viewModel.searchText.isEmpty {
                    Button(action: { viewModel.searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear filter")
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(colorScheme == .dark ? Color(white: 0.15) : Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .frame(maxWidth: 200)
            
            // Log level filters
            HStack(spacing: 4) {
                ForEach(WebSocketLogEntry.LogLevel.allCases, id: \.self) { level in
                    LogLevelFilterButton(
                        level: level,
                        isSelected: viewModel.selectedLevels.contains(level),
                        action: { viewModel.toggleLevel(level) }
                    )
                }
            }
            
            Spacer()
            
            // Component filter
            Menu {
                Button("All Components") {
                    viewModel.selectedComponent = nil
                }
                Divider()
                ForEach(viewModel.availableComponents, id: \.self) { component in
                    Button(component.displayName) {
                        viewModel.selectedComponent = component
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(viewModel.selectedComponent?.displayName ?? "All Components")
                        .font(.system(size: 10))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(colorScheme == .dark ? Color(white: 0.08) : Color(white: 0.95))
    }
    
    // MARK: - Log Entries
    
    private var logEntriesView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(viewModel.filteredEntries) { entry in
                        DrawerLogEntryRow(entry: entry)
                            .id(entry.id)
                    }
                }
                .padding(.horizontal, 12)
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
        .frame(height: 200)
        .background(colorScheme == .dark ? Color(white: 0.05) : Color.white)
    }
}

// MARK: - Drawer Log Entry Row

private struct DrawerLogEntryRow: View {
    let entry: WebSocketLogEntry
    @Environment(\.colorScheme) private var colorScheme
    
    private var levelColor: Color {
        switch entry.level {
        case .error: return .red
        case .warning: return .orange
        case .info: return .green
        case .debug: return .cyan
        case .verbose: return .gray
        }
    }
    
    private var timestampString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: entry.receivedAt)
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Timestamp
            Text(timestampString)
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 75, alignment: .leading)
            
            // Level badge
            Text(entry.level.rawValue)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(levelColor)
                .frame(width: 12)
            
            // Component
            Text(entry.component.displayName)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .leading)
                .lineLimit(1)
            
            // Message
            Text(entry.message)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .textSelection(.enabled)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
        .background(entry.level == .error ? Color.red.opacity(0.08) : Color.clear)
    }
}

// MARK: - Log Level Filter Button

private struct LogLevelFilterButton: View {
    let level: WebSocketLogEntry.LogLevel
    let isSelected: Bool
    let action: () -> Void
    
    private var levelColor: Color {
        switch level {
        case .error: return .red
        case .warning: return .orange
        case .info: return .green
        case .debug: return .cyan
        case .verbose: return .gray
        }
    }
    
    var body: some View {
        Button(action: action) {
            Text(level.rawValue)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(isSelected ? .white : levelColor)
                .frame(width: 18, height: 18)
                .background(isSelected ? levelColor : levelColor.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 3))
        }
        .buttonStyle(.plain)
        .help(level.displayName)
    }
}

// MARK: - View Model

@MainActor
class LogsDrawerViewModel: ObservableObject {
    @Published var entries: [WebSocketLogEntry] = []
    @Published var isRecording: Bool = false
    @Published var isConnected: Bool = false
    @Published var autoScroll: Bool = true
    
    // Filters
    @Published var searchText: String = ""
    @Published var selectedLevels: Set<WebSocketLogEntry.LogLevel> = Set(WebSocketLogEntry.LogLevel.allCases)
    @Published var selectedComponent: WebSocketLogEntry.LogComponent? = nil
    
    private let miner: Miner
    private var session: MinerWebsocketDataRecordingSession?
    private var cancellables = Set<AnyCancellable>()
    
    var filteredEntries: [WebSocketLogEntry] {
        entries.filter { entry in
            // Level filter
            guard selectedLevels.contains(entry.level) else { return false }
            
            // Component filter
            if let component = selectedComponent, entry.component != component {
                return false
            }
            
            // Search filter
            if !searchText.isEmpty {
                let query = searchText.lowercased()
                return entry.message.lowercased().contains(query) ||
                       entry.component.displayName.lowercased().contains(query)
            }
            
            return true
        }
    }
    
    var availableComponents: [WebSocketLogEntry.LogComponent] {
        let components = Set(entries.map { $0.component })
        return Array(components).sorted { $0.displayName < $1.displayName }
    }
    
    init(miner: Miner) {
        self.miner = miner
        // Don't setup session here - wait until drawer is expanded
    }
    
    private var isSessionSetup = false
    
    func setupSessionIfNeeded() {
        guard !isSessionSetup else { return }
        isSessionSetup = true
        
        // Get or create the websocket session for this miner
        session = MinerWebsocketRecordingSessionRegistry.shared.getOrCreateRecordingSession(
            minerHostName: miner.hostName,
            minerIpAddress: miner.ipAddress
        )
        
        guard let session = session else { return }
        
        // Subscribe to structured log entries
        session.structuredLogPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] entry in
                self?.entries.append(entry)
                // Keep only last 1000 entries in memory
                if let count = self?.entries.count, count > 1000 {
                    self?.entries.removeFirst(count - 1000)
                }
            }
            .store(in: &cancellables)
        
        // Subscribe to recording state
        session.recordingPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.isRecording = state != .idle
                self?.isConnected = state != .idle
            }
            .store(in: &cancellables)
        
        // Check initial state
        isRecording = session.state != .idle
        isConnected = session.state != .idle
    }
    
    func toggleRecording() {
        guard let session = session else { return }
        
        Task {
            if isRecording {
                await session.stopRecording()
            } else {
                await session.startRecording()
            }
        }
    }
    
    func clearLogs() {
        entries.removeAll()
    }
    
    func toggleLevel(_ level: WebSocketLogEntry.LogLevel) {
        if selectedLevels.contains(level) {
            selectedLevels.remove(level)
        } else {
            selectedLevels.insert(level)
        }
    }
}

