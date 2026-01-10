//
//  AppSettingsView.swift
//  HashRipper
//
//  Integrated settings view for the main app
//

import SwiftUI

struct AppSettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedSection: SettingsSection = .general
    
    enum SettingsSection: String, CaseIterable {
        case general = "General"
        case network = "Network"
    }
    
    var body: some View {
        HSplitView {
            // Sidebar
            settingsSidebar
                .frame(minWidth: 180, idealWidth: 200, maxWidth: 220)
            
            // Content - reuse existing settings views
            Group {
                switch selectedSection {
                case .general:
                    GeneralSettingsView()
                case .network:
                    NetworkSettingsView()
                }
            }
            .frame(minWidth: 500)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
    
    // MARK: - Sidebar
    
    private var settingsSidebar: some View {
        VStack(spacing: 0) {
            Text("Settings")
                .font(.system(size: 13, weight: .semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            
            Divider()
            
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(SettingsSection.allCases, id: \.self) { section in
                        SettingsSidebarRow(
                            title: section.rawValue,
                            icon: iconFor(section),
                            isSelected: selectedSection == section
                        ) {
                            withAnimation(.easeOut(duration: 0.12)) {
                                selectedSection = section
                            }
                        }
                    }
                }
                .padding(8)
            }
            
            Spacer()
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
    
    private func iconFor(_ section: SettingsSection) -> String {
        switch section {
        case .general: return "gearshape"
        case .network: return "network"
        }
    }
}

// MARK: - Sidebar Row

private struct SettingsSidebarRow: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(isSelected ? .blue : .secondary)
                    .frame(width: 20)
                
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}
