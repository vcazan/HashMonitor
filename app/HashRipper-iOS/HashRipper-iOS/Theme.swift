//
//  Theme.swift
//  HashRipper-iOS
//
//  Design system for consistent, professional styling
//

import SwiftUI

// MARK: - App Colors

struct AppColors {
    // Primary colors
    static let accent = Color.blue
    static let accentLight = Color.blue.opacity(0.1)
    
    // Text colors
    static let subtleText = Color(.secondaryLabel)
    static let mutedText = Color(.tertiaryLabel)
    
    // Background colors
    static let cardBackground = Color(.secondarySystemGroupedBackground)
    static let cardBorder = Color(.separator).opacity(0.5)
    
    // Semantic colors
    static let success = Color(red: 0.2, green: 0.7, blue: 0.4)
    static let successLight = Color(red: 0.2, green: 0.7, blue: 0.4).opacity(0.12)
    static let error = Color(red: 0.85, green: 0.25, blue: 0.25)
    static let errorLight = Color(red: 0.85, green: 0.25, blue: 0.25).opacity(0.1)
    static let warning = Color(red: 0.95, green: 0.65, blue: 0.15)
    static let warningLight = Color(red: 0.95, green: 0.65, blue: 0.15).opacity(0.12)
    
    // Data colors
    static let hashRate = Color(red: 0.3, green: 0.65, blue: 0.9)
    static let power = Color(red: 0.95, green: 0.6, blue: 0.2)
    static let frequency = Color(red: 0.55, green: 0.45, blue: 0.85)
    static let fan = Color(red: 0.3, green: 0.75, blue: 0.7)
    
    // Chart colors
    static let chartGreen = Color(red: 0.25, green: 0.75, blue: 0.45)
    static let chartOrange = Color(red: 0.95, green: 0.55, blue: 0.2)
    static let chartBlue = Color(red: 0.35, green: 0.55, blue: 0.9)
}

// MARK: - Temperature Color Helper

func temperatureColor(_ temp: Double) -> Color {
    switch temp {
    case ..<40:
        return AppColors.success
    case 40..<55:
        return Color(red: 0.95, green: 0.75, blue: 0.2)
    case 55..<70:
        return AppColors.warning
    default:
        return AppColors.error
    }
}

// MARK: - View Modifiers

struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(AppColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(AppColors.cardBorder, lineWidth: 0.5)
            )
    }
}

extension View {
    func cardStyle() -> some View {
        self.modifier(CardStyle())
    }
}

// MARK: - Common Components

struct StatusBadge: View {
    let isOnline: Bool
    var compact: Bool = false
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(isOnline ? AppColors.success : AppColors.error)
                .frame(width: compact ? 6 : 8, height: compact ? 6 : 8)
            
            if !compact {
                Text(isOnline ? "Online" : "Offline")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isOnline ? AppColors.success : AppColors.error)
            }
        }
        .padding(.horizontal, compact ? 6 : 8)
        .padding(.vertical, compact ? 3 : 4)
        .background((isOnline ? AppColors.success : AppColors.error).opacity(0.12))
        .clipShape(Capsule())
    }
}

struct StatBadge: View {
    let icon: String
    let value: String
    let unit: String
    let color: Color
    var iconColor: Color? = nil
    var compact: Bool = false
    
    var body: some View {
        HStack(spacing: compact ? 3 : 4) {
            Image(systemName: icon)
                .font(.system(size: compact ? 9 : 10, weight: .semibold))
                .foregroundStyle(iconColor ?? color)
            
            Text(value)
                .font(.system(size: compact ? 11 : 12, weight: .semibold, design: .rounded))
            
            Text(unit)
                .font(.system(size: compact ? 9 : 10, weight: .medium))
                .foregroundStyle(AppColors.mutedText)
        }
        .padding(.horizontal, compact ? 6 : 8)
        .padding(.vertical, compact ? 4 : 5)
        .background(color.opacity(0.1))
        .clipShape(Capsule())
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var buttonTitle: String? = nil
    var action: (() -> Void)? = nil
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: icon)
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(AppColors.mutedText)
            
            VStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 20, weight: .semibold))
                
                Text(message)
                    .font(.system(size: 14))
                    .foregroundStyle(AppColors.subtleText)
                    .multilineTextAlignment(.center)
            }
            
            if let buttonTitle = buttonTitle, let action = action {
                Button(action: action) {
                    Text(buttonTitle)
                        .frame(minWidth: 120)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppColors.accent)
                .controlSize(.large)
            }
        }
        .padding(32)
    }
}

struct SectionHeader: View {
    let title: String
    var count: Int? = nil
    
    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppColors.subtleText)
            
            if let count = count {
                Text("\(count)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppColors.mutedText)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(.tertiarySystemFill))
                    .clipShape(Capsule())
            }
            
            Spacer()
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Preview

#Preview("Theme Components") {
    ScrollView {
        VStack(spacing: 20) {
            // Status badges
            HStack {
                StatusBadge(isOnline: true)
                StatusBadge(isOnline: false)
                StatusBadge(isOnline: true, compact: true)
            }
            
            // Stat badges
            HStack {
                StatBadge(icon: "cube.fill", value: "525", unit: "GH/s", color: AppColors.hashRate)
                StatBadge(icon: "bolt.fill", value: "14.2", unit: "W", color: AppColors.power)
            }
            
            // Section header
            SectionHeader(title: "Devices", count: 3)
            
            // Empty state
            EmptyStateView(
                icon: "server.rack",
                title: "No Miners",
                message: "Add a miner to get started",
                buttonTitle: "Add Miner",
                action: { }
            )
            .cardStyle()
        }
        .padding()
    }
}
