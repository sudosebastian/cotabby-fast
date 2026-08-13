import Combine
import Foundation
import Logging

/// File overview:
/// Background multi-display OCR indexer. Captures every attached display with Vision `.fast`,
/// hygiene-filters the lines, attaches tiny sentence embeddings via `TextSemanticEmbedder`, and
/// publishes a `ScreenTextIndexSnapshot` for `ContextualRetriever`.
///
/// Critical path rule: suggestion generation never awaits this work. It reads `snapshot` (whatever
/// is already warm). Refresh is throttled and cancelled when Screen Recording is revoked or the
/// user disables ambient indexing / Fast Mode. Embedding fill runs in a detached utility task so
/// a ~1s batch encode cannot hitch the main actor after OCR returns.
@MainActor
final class AmbientScreenIndexer: ObservableObject {
    @Published private(set) var snapshot: ScreenTextIndexSnapshot = .empty
    @Published private(set) var isRefreshing = false

    private let displayCapture: DisplayScreenshotService
    private let textExtractor: ScreenTextExtractor
    private let embedder: TextSemanticEmbedder
    private let maxIndexedLines: Int
    private let minimumRefreshInterval: TimeInterval

    private var refreshTask: Task<Void, Never>?
    private var lastRefreshStartedAt: Date?
    private var isEnabled = false
    private var screenRecordingGranted = false

    /// Coalesce rapid triggers (app switch storms) into one refresh.
    private var pendingRefresh = false

    init(
        displayCapture: DisplayScreenshotService = DisplayScreenshotService(),
        embedder: TextSemanticEmbedder = .shared,
        maxImageDimension: Int = 900,
        maxIndexedLines: Int = 300,
        minimumRefreshInterval: TimeInterval = 3.0
    ) {
        self.displayCapture = displayCapture
        self.embedder = embedder
        self.textExtractor = ScreenTextExtractor(
            maxImageDimension: maxImageDimension,
            maxRecognizedCharacters: 8_000,
            recognitionLevel: .fast,
            usesLanguageCorrection: false
        )
        self.maxIndexedLines = maxIndexedLines
        self.minimumRefreshInterval = minimumRefreshInterval
    }

    /// Enables or disables ambient indexing. When disabled, cancels in-flight work but keeps the
    /// last snapshot so a brief toggle-off does not blank retrieval mid-keystroke.
    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if !enabled {
            refreshTask?.cancel()
            refreshTask = nil
            isRefreshing = false
            pendingRefresh = false
        } else {
            requestRefresh(reason: "enabled")
        }
    }

    func setScreenRecordingGranted(_ granted: Bool) {
        screenRecordingGranted = granted
        if !granted {
            refreshTask?.cancel()
            refreshTask = nil
            isRefreshing = false
            snapshot = .empty
        } else if isEnabled {
            requestRefresh(reason: "permission-granted")
        }
    }

    /// Schedules a refresh if enabled, permitted, and outside the throttle window.
    func requestRefresh(reason: String) {
        guard isEnabled, screenRecordingGranted else { return }

        if let last = lastRefreshStartedAt,
           Date().timeIntervalSince(last) < minimumRefreshInterval {
            pendingRefresh = true
            return
        }

        guard refreshTask == nil else {
            pendingRefresh = true
            return
        }

        lastRefreshStartedAt = Date()
        pendingRefresh = false
        isRefreshing = true
        CotabbyLogger.app.debug("Ambient screen refresh starting reason=\(reason)")

        refreshTask = Task { [weak self] in
            await self?.runRefresh()
        }
    }

    private func runRefresh() async {
        defer {
            refreshTask = nil
            isRefreshing = false
            if pendingRefresh {
                pendingRefresh = false
                requestRefresh(reason: "coalesced")
            }
        }

        do {
            let captures = try await displayCapture.captureAllDisplays()
            guard !Task.isCancelled else { return }

            var allLines: [ScreenTextIndexLine] = []
            let capturedAt = Date()

            let extractor = textExtractor
            await withTaskGroup(of: [ScreenTextIndexLine].self) { group in
                for capture in captures {
                    group.addTask {
                        await Self.extractLines(
                            from: capture,
                            capturedAt: capturedAt,
                            extractor: extractor
                        )
                    }
                }
                for await lines in group {
                    allLines.append(contentsOf: lines)
                }
            }

            guard !Task.isCancelled else { return }

            // Prefer higher-confidence lines; cap total indexed volume.
            allLines.sort { $0.confidence > $1.confidence }
            if allLines.count > maxIndexedLines {
                allLines = Array(allLines.prefix(maxIndexedLines))
            }

            guard !Task.isCancelled else { return }

            // Sentence embeddings are the slow part of indexing (~1s for a few hundred lines). Keep
            // them off the main actor; the suggestion path reads the previous snapshot until this
            // detached fill publishes a replacement.
            let embedder = self.embedder
            let embeddedLines = await Task.detached(priority: .utility) {
                embedder.embeddingFilled(lines: allLines)
            }.value

            guard !Task.isCancelled else { return }

            let embeddedCount = embeddedLines.reduce(0) { partial, line in
                partial + (line.embedding == nil ? 0 : 1)
            }
            snapshot = ScreenTextIndexSnapshot(lines: embeddedLines, updatedAt: capturedAt)
            CotabbyLogger.app.debug(
                "Ambient screen refresh ready displays=\(captures.count) lines=\(embeddedLines.count) embedded=\(embeddedCount)"
            )
        } catch {
            CotabbyLogger.app.debug("Ambient screen refresh failed reason=\(error.localizedDescription)")
        }
    }

    private nonisolated static func extractLines(
        from capture: CapturedDisplayScreenshot,
        capturedAt: Date,
        extractor: ScreenTextExtractor
    ) async -> [ScreenTextIndexLine] {
        do {
            let extracted = try await extractor.extractText(from: capture.image)
            let cleanedText = OCRTextHygiene.clean(
                lines: extracted.lines,
                fieldText: "",
                maxChars: 4_000
            )
            return cleanedText
                .split(whereSeparator: \.isNewline)
                .map { line in
                    let text = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
                    // Hygiene drops low-confidence lines already; assign a mid confidence so
                    // retrieval still prefers field OCR when scores are otherwise tied.
                    return ScreenTextIndexLine(
                        text: text,
                        displayID: capture.displayID,
                        confidence: 0.7,
                        capturedAt: capturedAt,
                        windowHint: nil
                    )
                }
                .filter { !$0.text.isEmpty }
        } catch {
            return []
        }
    }
}
