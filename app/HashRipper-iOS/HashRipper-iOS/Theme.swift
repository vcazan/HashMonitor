//
//  Theme.swift
//  HashMonitor
//
//  Apple Design Language Implementation
//  Inspired by Home, Health, and Weather apps
//

import SwiftUI

// MARK: - Design Tokens

/// Apple-style spacing system based on 4pt grid
enum Spacing {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
    static let xxxl: CGFloat = 32
}

/// Corner radius tokens
enum Radius {
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let full: CGFloat = 100
}

// MARK: - App Colors (Adaptive)

struct AppColors {
    // MARK: - Semantic Colors
    
    /// Primary accent - a refined teal/cyan inspired by Apple's system teal
    static let accent = Color("AccentColor", bundle: nil)
    static let accentTint = Color.teal
    
    // MARK: - Text Hierarchy
    static let textPrimary = Color(.label)
    static let textSecondary = Color(.secondaryLabel)
    static let textTertiary = Color(.tertiaryLabel)
    static let textQuaternary = Color(.quaternaryLabel)
    
    // MARK: - Backgrounds (Semantic)
    static let backgroundPrimary = Color(.systemBackground)
    static let backgroundSecondary = Color(.secondarySystemBackground)
    static let backgroundTertiary = Color(.tertiarySystemBackground)
    static let backgroundGrouped = Color(.systemGroupedBackground)
    static let backgroundGroupedSecondary = Color(.secondarySystemGroupedBackground)
    
    // MARK: - Fill Colors
    static let fill = Color(.systemFill)
    static let fillSecondary = Color(.secondarySystemFill)
    static let fillTertiary = Color(.tertiarySystemFill)
    static let fillQuaternary = Color(.quaternarySystemFill)
    
    // MARK: - Status Colors (Muted, Apple-style)
    static let statusOnline = Color(red: 0.30, green: 0.69, blue: 0.31)  // Soft green
    static let statusOffline = Color(red: 0.95, green: 0.33, blue: 0.31) // Soft red
    static let statusWarning = Color(red: 1.0, green: 0.62, blue: 0.04)  // Soft orange
    
    // MARK: - Data Visualization Colors (Monochromatic server-style)
    static let hashRate = Color(red: 0.30, green: 0.69, blue: 0.31)      // Green (same as online)
    static let power = Color(.secondaryLabel)                             // Gray
    static let temp = Color(.secondaryLabel)                              // Gray
    static let frequency = Color(.secondaryLabel)                         // Gray
    static let shares = Color(red: 0.30, green: 0.69, blue: 0.31)         // Green
    static let efficiency = Color(.secondaryLabel)                        // Gray
    
    // MARK: - Chart Colors
    static let chartLine = Color(red: 0.30, green: 0.69, blue: 0.31)     // Green
    static let chartGradientTop = Color(red: 0.30, green: 0.69, blue: 0.31).opacity(0.3)
    static let chartGradientBottom = Color(red: 0.30, green: 0.69, blue: 0.31).opacity(0.0)
    
    // MARK: - Primary Accent (Green)
    static let primaryAccent = Color(red: 0.30, green: 0.69, blue: 0.31)
    
    // MARK: - Separator
    static let separator = Color(.separator)
    static let separatorOpaque = Color(.opaqueSeparator)
}

// MARK: - Temperature Color Helper

func temperatureColor(_ temp: Double) -> Color {
    switch temp {
    case ..<45: return AppColors.statusOnline
    case 45..<60: return AppColors.statusWarning
    default: return AppColors.statusOffline
    }
}

// MARK: - Typography (SF Pro)

extension Font {
    // MARK: - Display
    static let displayLarge = Font.system(size: 34, weight: .bold, design: .rounded)
    static let displayMedium = Font.system(size: 28, weight: .bold, design: .rounded)
    static let displaySmall = Font.system(size: 22, weight: .bold, design: .rounded)
    
    // MARK: - Title
    static let titleLarge = Font.system(size: 20, weight: .semibold)
    static let titleMedium = Font.system(size: 17, weight: .semibold)
    static let titleSmall = Font.system(size: 15, weight: .semibold)
    
    // MARK: - Body
    static let bodyLarge = Font.system(size: 17, weight: .regular)
    static let bodyMedium = Font.system(size: 15, weight: .regular)
    static let bodySmall = Font.system(size: 13, weight: .regular)
    
    // MARK: - Caption
    static let captionLarge = Font.system(size: 12, weight: .medium)
    static let captionMedium = Font.system(size: 11, weight: .medium)
    static let captionSmall = Font.system(size: 10, weight: .medium)
    
    // MARK: - Numeric (Rounded for data)
    static let numericLarge = Font.system(size: 34, weight: .bold, design: .rounded)
    static let numericMedium = Font.system(size: 24, weight: .semibold, design: .rounded)
    static let numericSmall = Font.system(size: 17, weight: .semibold, design: .rounded)
    
    // MARK: - Monospaced (for technical data)
    static let monoLarge = Font.system(size: 15, weight: .medium, design: .monospaced)
    static let monoMedium = Font.system(size: 13, weight: .medium, design: .monospaced)
    static let monoSmall = Font.system(size: 11, weight: .medium, design: .monospaced)
}

// MARK: - View Modifiers

/// Apple-style card with subtle elevation
struct AppleCard: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    
    var padding: CGFloat = Spacing.lg
    var cornerRadius: CGFloat = Radius.lg
    
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(AppColors.backgroundGroupedSecondary)
                    .shadow(
                        color: colorScheme == .dark ? .clear : .black.opacity(0.04),
                        radius: 8,
                        x: 0,
                        y: 2
                    )
            )
    }
}

/// Glassy material card (like Control Center)
struct GlassCard: ViewModifier {
    var cornerRadius: CGFloat = Radius.lg
    
    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// Subtle press animation
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

extension View {
    func appleCard(padding: CGFloat = Spacing.lg, cornerRadius: CGFloat = Radius.lg) -> some View {
        modifier(AppleCard(padding: padding, cornerRadius: cornerRadius))
    }
    
    func glassCard(cornerRadius: CGFloat = Radius.lg) -> some View {
        modifier(GlassCard(cornerRadius: cornerRadius))
    }
}

// MARK: - Reusable Components

/// Status indicator dot (Apple-style)
struct StatusDot: View {
    let isOnline: Bool
    var size: CGFloat = 8
    
    var body: some View {
        Circle()
            .fill(isOnline ? AppColors.statusOnline : AppColors.statusOffline)
            .frame(width: size, height: size)
            .shadow(color: (isOnline ? AppColors.statusOnline : AppColors.statusOffline).opacity(0.5), radius: size/2)
    }
}

/// Compact status badge (like Apple Mail)
struct StatusBadge: View {
    let isOnline: Bool
    var showLabel: Bool = true
    
    var body: some View {
        HStack(spacing: Spacing.xs) {
            StatusDot(isOnline: isOnline, size: 6)
            
            if showLabel {
                Text(isOnline ? "Online" : "Offline")
                    .font(.captionMedium)
                    .foregroundStyle(isOnline ? AppColors.statusOnline : AppColors.statusOffline)
            }
        }
        .padding(.horizontal, showLabel ? Spacing.sm : Spacing.xs)
        .padding(.vertical, Spacing.xs)
        .background(
            Capsule()
                .fill((isOnline ? AppColors.statusOnline : AppColors.statusOffline).opacity(0.12))
        )
    }
}

/// Clean stat display (Server dashboard style)
struct StatDisplay: View {
    let value: String
    let unit: String
    let label: String
    let icon: String
    let color: Color
    
    @State private var hasAppeared = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Label
            Text(label)
                .font(.captionLarge)
                .foregroundStyle(AppColors.textTertiary)
            
            // Value
            HStack(alignment: .lastTextBaseline, spacing: Spacing.xxs) {
                Text(value)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppColors.textPrimary)
                    .contentTransition(.numericText())
                
                Text(unit)
                    .font(.captionLarge)
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(AppColors.backgroundGroupedSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .stroke(AppColors.separator.opacity(0.5), lineWidth: 0.5)
                )
        )
        .opacity(hasAppeared ? 1 : 0)
        .offset(y: hasAppeared ? 0 : 10)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.1)) {
                hasAppeared = true
            }
        }
    }
}

/// Compact stat badge (for lists)
struct StatBadge: View {
    let icon: String
    let value: String
    let unit: String
    let color: Color
    var compact: Bool = false
    
    var body: some View {
        HStack(spacing: Spacing.xxs) {
            Image(systemName: icon)
                .font(.system(size: compact ? 9 : 10, weight: .semibold))
                .foregroundStyle(color)
            
            Text(value)
                .font(compact ? .captionMedium : .captionLarge)
                .fontWeight(.semibold)
                .fontDesign(.rounded)
            
            Text(unit)
                .font(.captionSmall)
                .foregroundStyle(AppColors.textTertiary)
        }
        .padding(.horizontal, compact ? Spacing.sm : Spacing.md)
        .padding(.vertical, compact ? Spacing.xs : Spacing.sm)
        .background(color.opacity(0.1))
        .clipShape(Capsule())
    }
}

/// Empty state view (Apple-style)
struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var buttonTitle: String? = nil
    var action: (() -> Void)? = nil
    
    var body: some View {
        VStack(spacing: Spacing.xl) {
            // Icon with gradient background
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [AppColors.fillSecondary, AppColors.fillTertiary],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)
                
                Image(systemName: icon)
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(AppColors.textTertiary)
            }
            
            VStack(spacing: Spacing.sm) {
                Text(title)
                    .font(.titleMedium)
                    .foregroundStyle(AppColors.textPrimary)
                
                Text(message)
                    .font(.bodySmall)
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
            }
            
            if let buttonTitle = buttonTitle, let action = action {
                Button(action: action) {
                    Text(buttonTitle)
                        .font(.bodyMedium)
                        .fontWeight(.semibold)
                        .padding(.horizontal, Spacing.xxl)
                        .padding(.vertical, Spacing.md)
                }
                .buttonStyle(.borderedProminent)
                .tint(.teal)
            }
        }
        .padding(Spacing.xxxl)
    }
}

/// Section header (Settings-style)
struct SectionHeader: View {
    let title: String
    var count: Int? = nil
    var action: (() -> Void)? = nil
    var actionLabel: String? = nil
    
    var body: some View {
        HStack(alignment: .center) {
            Text(title.uppercased())
                .font(.captionMedium)
                .foregroundStyle(AppColors.textSecondary)
                .tracking(0.5)
            
            if let count = count {
                Text("\(count)")
                    .font(.captionMedium)
                    .foregroundStyle(AppColors.textTertiary)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.xxs)
                    .background(AppColors.fillTertiary)
                    .clipShape(Capsule())
            }
            
            Spacer()
            
            if let action = action, let label = actionLabel {
                Button(action: action) {
                    Text(label)
                        .font(.captionLarge)
                        .foregroundStyle(.teal)
                }
            }
        }
        .padding(.horizontal, Spacing.xs)
    }
}

/// Mini graph sparkline
struct Sparkline: View {
    let data: [Double]
    let color: Color
    
    var body: some View {
        GeometryReader { geometry in
            let maxVal = data.max() ?? 1
            let minVal = data.min() ?? 0
            let range = maxVal - minVal
            let normalizedData = data.map { range > 0 ? ($0 - minVal) / range : 0.5 }
            
            Path { path in
                guard normalizedData.count > 1 else { return }
                
                let stepX = geometry.size.width / CGFloat(normalizedData.count - 1)
                
                path.move(to: CGPoint(
                    x: 0,
                    y: geometry.size.height * (1 - normalizedData[0])
                ))
                
                for (index, value) in normalizedData.enumerated().dropFirst() {
                    path.addLine(to: CGPoint(
                        x: stepX * CGFloat(index),
                        y: geometry.size.height * (1 - value)
                    ))
                }
            }
            .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
    }
}

// MARK: - Haptics

struct Haptics {
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
    
    static func notification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }
    
    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }
}

// MARK: - Preview

#Preview("Design System") {
    ScrollView {
        VStack(spacing: Spacing.xxl) {
            // Status badges
            HStack(spacing: Spacing.md) {
                StatusBadge(isOnline: true)
                StatusBadge(isOnline: false)
                StatusBadge(isOnline: true, showLabel: false)
            }
            
            // Stat displays
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Spacing.md) {
                StatDisplay(value: "524", unit: "GH/s", label: "Hash Rate", icon: "cube.fill", color: AppColors.hashRate)
                StatDisplay(value: "14.2", unit: "W", label: "Power", icon: "bolt.fill", color: AppColors.power)
                StatDisplay(value: "52", unit: "°C", label: "Temperature", icon: "thermometer.medium", color: AppColors.temp)
                StatDisplay(value: "575", unit: "MHz", label: "Frequency", icon: "waveform", color: AppColors.frequency)
            }
            .padding(.horizontal)
            
            // Stat badges
            HStack(spacing: Spacing.sm) {
                StatBadge(icon: "cube.fill", value: "524", unit: "GH/s", color: AppColors.hashRate)
                StatBadge(icon: "bolt.fill", value: "14.2", unit: "W", color: AppColors.power, compact: true)
            }
            
            // Empty state
            EmptyStateView(
                icon: "cpu",
                title: "No Miners",
                message: "Add a miner to start monitoring your Bitcoin mining devices",
                buttonTitle: "Add Miner",
                action: { }
            )
            .appleCard()
            .padding(.horizontal)
            
            // Section header
            SectionHeader(title: "Devices", count: 3, action: {}, actionLabel: "See All")
                .padding(.horizontal)
        }
        .padding(.vertical)
    }
    .background(AppColors.backgroundGrouped)
}
