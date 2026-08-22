import Combine
import SwiftUI

/// File overview:
/// Always-visible menu-bar label. Kept separate from the panel so the status item stays tiny.
///
/// Observes settings for pause/enable chrome and only the word-count publisher from the
/// coordinator — not the coordinator as `@ObservedObject`. Visual-context and overlay publishes
/// on `SuggestionCoordinator` would otherwise redraw this label on every OCR/status tick.
struct MenuBarStatusLabelView: View {
    let suggestionCoordinator: SuggestionCoordinator
    @ObservedObject var suggestionSettings: SuggestionSettingsModel

    @State private var totalTabAcceptedWordCount: Int = 0

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "forward.end.fill")
                .font(.system(size: 13, weight: .semibold))
                .accessibilityLabel("Tabfast")

            if suggestionSettings.isTemporarilyPaused || !suggestionSettings.isGloballyEnabled {
                Image(systemName: "pause.fill")
                    .font(.system(size: 8, weight: .bold))
                    .accessibilityLabel(inactiveAccessibilityLabel)
            }

            if suggestionSettings.isMenuBarWordCountVisible,
               let label = WordCountFormatter.compactLabel(for: totalTabAcceptedWordCount) {
                Text(label)
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
            }
        }
        .onAppear {
            totalTabAcceptedWordCount = suggestionCoordinator.totalTabAcceptedWordCount
        }
        .onReceive(suggestionCoordinator.$totalTabAcceptedWordCount) { count in
            totalTabAcceptedWordCount = count
        }
    }

    private var inactiveAccessibilityLabel: String {
        suggestionSettings.isGloballyEnabled ? "Tabfast paused" : "Tabfast disabled"
    }
}
