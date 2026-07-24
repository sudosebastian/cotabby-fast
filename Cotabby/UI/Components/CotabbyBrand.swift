import SwiftUI

/// File overview:
/// Cotabby's brand palette, shared by every surface that speaks in the brand voice (onboarding,
/// the permission reminder, and the Settings Home hero). Pinned rather than derived from
/// `Color.accentColor` so brand moments stay on-brand even when the user picks a different system
/// accent; ordinary interactive controls should keep following the system accent.
enum CotabbyBrand {
    /// Electric cyan sampled from Tabfast's forward mark. Identical in both appearances.
    static let accent = Color(red: 0.0, green: 0.82, blue: 0.94)

    /// Lighter companion to `accent`, used as the top stop of icon-tile and pip gradients so
    /// tinted elements read as lit from above (the System Settings icon treatment).
    static let accentSoft = Color(red: 0.40, green: 0.30, blue: 0.96)
}
