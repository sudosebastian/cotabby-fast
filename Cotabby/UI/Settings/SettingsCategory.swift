import SwiftUI

/// File overview:
/// The catalog of sidebar rows in the Settings window. The sidebar renders these as visually
/// clustered groups (see `sidebarGroups`) without header text: System Settings-style labeled
/// headers were tried earlier but the extra chrome ate sidebar width and pushed labels into
/// truncation, so the grouping is carried by spacing alone. Engine-specific content (Apple
/// Intelligence vs. Open Source) lives inside the single Engine & Model pane and is switched via
/// the engine dropdown at the top of that pane.
///
/// Order reflects a top-down reading: core behavior, how suggestions look, the emoji feature, what
/// the model is told (writing then context), the model itself, input bindings, then system and info.
enum SettingsCategory: String, CaseIterable, Hashable, Identifiable {
    case home
    case general
    case appearance
    case emoji
    case writing
    case context
    case engineAndModel
    case shortcuts
    case apps
    case permissions
    case performance
    case about

    var id: String { rawValue }

    var label: String {
        switch self {
        case .home: return "Home"
        case .general: return "General"
        case .appearance: return "Appearance"
        case .emoji: return "Emoji"
        case .writing: return "Writing"
        case .context: return "Context"
        case .engineAndModel: return "Engine & Model"
        case .shortcuts: return "Shortcuts"
        case .apps: return "Apps"
        case .permissions: return "Permissions"
        case .performance: return "Performance"
        case .about: return "About"
        }
    }

    /// SF Symbol displayed in the sidebar tile and anywhere else the category is represented.
    var systemImage: String {
        switch self {
        case .home: return "house.fill"
        case .general: return "gearshape.fill"
        case .appearance: return "paintbrush.fill"
        case .emoji: return "face.smiling"
        case .writing: return "square.and.pencil"
        case .context: return "doc.text"
        case .engineAndModel: return "cpu.fill"
        case .shortcuts: return "keyboard.fill"
        case .apps: return "app.badge.fill"
        case .permissions: return "lock.shield.fill"
        case .performance: return "speedometer"
        case .about: return "info.circle.fill"
        }
    }

    /// Tile tint behind the white symbol, mirroring System Settings' colored sidebar icons. The
    /// same tint colors the category's search results and Home quick links so a pane keeps one
    /// identity everywhere it appears.
    var tint: Color {
        switch self {
        case .home: return TabfastDesign.ColorToken.accent
        case .general: return .gray
        case .appearance: return Color(red: 0.35, green: 0.45, blue: 0.75)
        case .emoji: return .yellow
        case .writing: return Color(red: 0.20, green: 0.55, blue: 0.50)
        case .context: return .teal
        case .engineAndModel: return .orange
        case .shortcuts: return Color(red: 0.75, green: 0.35, blue: 0.40)
        case .apps: return Color(red: 0.70, green: 0.30, blue: 0.30)
        case .permissions: return TabfastDesign.ColorToken.accentDeep
        case .performance: return .green
        case .about: return .gray
        }
    }

    /// One-line caption used by the Home quick-link cards.
    var summary: String {
        switch self {
        case .home: return "Search and status"
        case .general: return "Power and startup"
        case .appearance: return "Ghost text look"
        case .emoji: return "Inline emoji picker"
        case .writing: return "Length and profile"
        case .context: return "What the model sees"
        case .engineAndModel: return "Engine and models"
        case .shortcuts: return "Accept keys"
        case .apps: return "Quiet apps"
        case .permissions: return "System access"
        case .performance: return "Latency and quality"
        case .about: return "Version and licenses"
        }
    }

    /// Sidebar clusters, in display order. Spacing between groups (not headers) carries the
    /// structure: landing, everyday behavior and look, the intelligence itself, control and
    /// access, then diagnostics and info. Every case must appear exactly once; a unit test
    /// pins that invariant so a new pane cannot silently vanish from the sidebar.
    static let sidebarGroups: [[SettingsCategory]] = [
        [.home],
        [.general, .appearance, .emoji],
        [.writing, .context, .engineAndModel],
        [.shortcuts, .apps, .permissions],
        [.performance, .about]
    ]
}
