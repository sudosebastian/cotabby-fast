import Combine
import Foundation

/// File overview:
/// Declares the shared state and dependency graph for Cotabby's inline-completion orchestrator.
/// The behavior now lives in `SuggestionCoordinator+*.swift` files so maintainers can read the
/// state machine by concern instead of scrolling through one monolithic source file.
///
/// Swift does not offer a "type-private across multiple files" access level. Because this
/// coordinator is split across extension files, coordinator-owned mutable state uses module
/// visibility and is protected by convention: other types should observe these properties, not
/// mutate them.
@MainActor
final class SuggestionCoordinator: ObservableObject {
    /// Coordinator-owned state machine values. Tests inspect these directly, but no UI subscribes
    /// to them, so keeping them as plain properties avoids unrelated menu re-renders.
    var state: SuggestionDebugState = .idle
    var overlayState: OverlayState = .hidden(reason: "Overlay idle.")
    var latestGenerationNumber: UInt64?
    @Published var visualContextStatus: VisualContextStatus = .idle
    @Published var latestVisualContextText: String?
    @Published var totalTabAcceptedWordCount: Int = 0

    // Core collaborators. The coordinator depends on capability-shaped protocols here so its
    // orchestration logic stays separated from concrete service implementations.
    let permissionManager: any SuggestionPermissionProviding
    let focusModel: any SuggestionFocusProviding
    let inputMonitor: any SuggestionInputMonitoring
    let overlayController: any SuggestionOverlayControlling
    let suggestionInserter: any SuggestionInserting
    let suggestionEngine: any SuggestionGenerating
    let suggestionSettings: any SuggestionSettingsProviding
    let clipboardContextProvider: any ClipboardContextProviding
    let clipboardRelevanceFilter: any ClipboardRelevanceFiltering
    let visualContextCoordinator: any VisualContextCoordinating
    /// Local rare-term / n-gram memory learned from Tab accepts.
    let writingMemoryStore: WritingMemoryStore
    /// Recent focused surfaces used only as a retrieval ranking prior.
    let recentFocusRing: RecentFocusRing
    /// Background multi-display OCR index; never awaited on the keystroke path.
    let ambientScreenIndexer: AmbientScreenIndexer
    let interactionState: SuggestionInteractionState
    let workController: SuggestionWorkController
    let configuration: SuggestionConfiguration
    let userDefaults: UserDefaults
    let overlayPresenter: SuggestionOverlayPresenter
    let logger: SuggestionDebugLogger
    /// Drives the typo gate before each prediction. Owned at app scope (constructed once in
    /// `CotabbyAppEnvironment`) so the underlying `NSSpellChecker` document tag persists across the
    /// coordinator's lifetime instead of churning per keystroke.
    let spellChecker: CurrentWordSpellChecker
    /// Always-on quality counters (shown / suppressed / accepted). The router counts generation
    /// outcomes; the coordinator owns the display-time and acceptance events only it can see.
    let qualityMetricsStore: SuggestionQualityMetricsStore
    /// Frequency-ranked correction source (SymSpell). Used first for the correction word, with
    /// `spellChecker` as the fallback while its index is still loading or when it has no suggestion.
    let symSpellCorrector: SymSpellCorrector
    /// Chooses at most one enabled SymSpell language from the text surrounding the typo. Ambiguous
    /// contexts return nil so correction ranking falls back to the system spell checker.
    let spellingLanguageResolver: SpellingLanguageResolver

    /// Returns true when the loaded llama model has rejected partial KV trims. Used to shrink the
    /// Open Source prompt budget on the full-reprefill path. Defaults to false so tests that do
    /// not wire a runtime still build the standard prompt.
    let llamaRejectsPartialKVTrimsProvider: () -> Bool

    /// Optional first-look hook the emoji picker installs to observe the keystroke stream. Called at
    /// the very top of `handleInputEvent`, before any suggestion logic. Returns `true` when an emoji
    /// capture is involved with this key, in which case the coordinator stands down so ghost text does
    /// not compete with the picker. It never consumes keys here (the listen-only observer cannot);
    /// consumption happens through `InputMonitor.emojiCaptureKeyDecider`.
    var emojiInputObserver: ((CapturedInputEvent) -> Bool)?

    static let totalTabAcceptedWordCountDefaultsKey = "cotabbyTotalAcceptedWordCount"

    // Combine subscriptions are the coordinator's remaining direct mutable bookkeeping.
    // Async work and active-session storage now live in dedicated collaborators below.
    var cancellables = Set<AnyCancellable>()
    var settingsSnapshot: SuggestionSettingsSnapshot
    /// Last completed round trip per backend, retained across keystrokes. Keeping this separate lets
    /// a slow HTTP backend retain an appropriate debounce without leaking that latency into the
    /// in-process engines.
    var lastLatencyByEngine: [SuggestionEngineKind: Int] = [:]
    // Synchronous input/focus callbacks cannot directly `await`, so resets are represented as a
    // barrier task that the next generation must cross before it can ask the runtime for output.
    var cacheResetSequence: UInt64 = 0
    var pendingCacheReset: (sequence: UInt64, task: Task<Void, Never>)?
    /// One accepted clipboard-relevance verdict per (field session, pasteboard state). The verdict
    /// used to be re-evaluated against the live prefix on every request, and because the clipboard
    /// section precedes the typed prefix in the prompt, every flip rewrote the prompt HEAD and
    /// collapsed the engine's reusable common prefix back to zero (a full re-prefill). A pinned
    /// non-nil verdict keeps the prompt head stable for the field session; a nil verdict keeps
    /// re-evaluating because adding nothing to the prompt cannot destabilize the head, and the
    /// clipboard may only become relevant once more text is typed. A new copy (change count) or a
    /// field switch (focus sequence) always re-evaluates. See `pinnedClipboardContext`.
    struct ClipboardPrefaceMemo {
        let focusSequence: UInt64
        let changeCount: Int
        let value: String?
    }

    var clipboardPrefaceMemo: ClipboardPrefaceMemo?
    /// Coalescing and monotonic-render state for engine partials. The coordinator owns scheduling
    /// and presentation; the value owns the stream's pure state transitions.
    var suggestionStreamingState = SuggestionStreamingState()

    /// Monotonic cancellation token for the "wait until the host publishes typed text to AX" loop.
    ///
    /// Keystrokes can arrive faster than Chromium publishes contenteditable updates. Without this
    /// token, every key starts its own delayed polling chain and those chains stack up, each doing
    /// synchronous `refreshNow()` calls on the main actor. Bumping the token makes older chains
    /// no-op before they can perform another expensive AX read.
    var hostPublishPollGeneration: UInt64 = 0
    /// Baseline retained when the host-publish poll hits its ceiling without observing an AX change.
    /// Generating against that pre-keystroke snapshot produced ghost text that looked like Cotabby
    /// swallowed the typed character; instead we stand down and let a later real publish (via the
    /// focus timer) schedule against the post-keystroke text. Cleared on a new keystroke, cancel,
    /// or a successful late-publish schedule.
    var pendingLateHostPublish: LateHostPublishBaseline?
    /// Suppresses single-poll `Supported → Blocked → Supported` flicker on the same focused element
    /// so the overlay does not tear down and rebuild on every transient AX redraw. See
    /// `FocusCapabilityFlickerGate` for the rationale and the reproduction (Apple Calendar event
    /// editor).
    var capabilityFlickerGate = FocusCapabilityFlickerGate()
    /// Correlation ID for the most recently built `SuggestionRequest`. Stamped onto every
    /// state-transition log line so all events tied to one suggestion (debounce → generating →
    /// ready → accepted/rejected) can be joined with a single `jq` filter on `request_id`.
    /// `nil` between sessions; replaced when `+Prediction` builds the next request.
    var latestRequestID: String?
    /// Set when a full acceptance commits its final chunk; consumed by the next `apply`. Lets the
    /// coordinator drop a regeneration that only re-proposes the just-accepted tail before the host
    /// publishes the insert, the Chromium AX-publish race that otherwise loops accept/regenerate/
    /// accept on the last word. See `SuggestionSessionReconciler.isStaleAcceptanceEcho`.
    var lastAcceptedTail: AcceptedSuggestionTail?

    /// Wall-clock moment of the most recent committed acceptance. The stability gate uses its age
    /// to scope the backward-drift hold: only geometry read shortly after our own insert can be
    /// the stale-frame kind, so older backward corrections stay re-anchorable.
    var lastAcceptanceAt: Date?

    /// Bounded string-only memory of recent suggestions for instant re-show on rollback and
    /// re-entry (see `SuggestionAnchorCache`). `cotabbyAnchorReuseDisabled` is the kill switch.
    var suggestionAnchorCache = SuggestionAnchorCache()
    static let anchorReuseDisabledDefaultsKey = "cotabbyAnchorReuseDisabled"
    static let speculativePrefetchDisabledDefaultsKey = "cotabbySpeculativePrefetchDisabled"

    /// Content signature a speculative post-acceptance generation was built against. While set,
    /// `apply` may accept a result whose generation predates the live one as long as the live
    /// content matches this signature (the speculation bet paid off), and the host-publish poll
    /// stands down instead of scheduling a duplicate regeneration.
    var pendingSpeculativeSignature: String?

    /// Pure state for the bounded "keep owning Tab" window after a final-chunk acceptance. The
    /// coordinator continues to own the timer and input-monitor effects around these transitions.
    var postExhaustionAcceptanceState = PostExhaustionAcceptanceState()

    /// Pending idle-arm for the accept tap while a streamed ghost is visible under `.generating`.
    /// Cancelled on every new partial, on hide, and when the suggestion reaches `.ready`.
    var acceptInterceptionArmWorkItem: DispatchWorkItem?

    /// How long streaming must go quiet before we install the system-wide accept `defaultTap`.
    /// During an active stream, holding that tap gates every keyDown on MainActor and was freezing
    /// / dropping typed characters. A short idle still allows early Tab once tokens pause.
    static let streamAcceptArmIdleMilliseconds = 120

    init(
        permissionManager: any SuggestionPermissionProviding,
        focusModel: any SuggestionFocusProviding,
        inputMonitor: any SuggestionInputMonitoring,
        overlayController: any SuggestionOverlayControlling,
        suggestionInserter: any SuggestionInserting,
        suggestionEngine: any SuggestionGenerating,
        suggestionSettings: any SuggestionSettingsProviding,
        clipboardContextProvider: any ClipboardContextProviding,
        clipboardRelevanceFilter: any ClipboardRelevanceFiltering,
        visualContextCoordinator: any VisualContextCoordinating,
        writingMemoryStore: WritingMemoryStore? = nil,
        recentFocusRing: RecentFocusRing? = nil,
        ambientScreenIndexer: AmbientScreenIndexer? = nil,
        interactionState: SuggestionInteractionState,
        workController: SuggestionWorkController,
        configuration: SuggestionConfiguration,
        spellChecker: CurrentWordSpellChecker,
        symSpellCorrector: SymSpellCorrector,
        spellingLanguageResolver: SpellingLanguageResolver = SpellingLanguageResolver(),
        qualityMetricsStore: SuggestionQualityMetricsStore,
        userDefaults: UserDefaults = .standard,
        llamaRejectsPartialKVTrimsProvider: @escaping () -> Bool = { false }
    ) {
        let storedTotalTabAcceptedWordCount = userDefaults.integer(
            forKey: Self.totalTabAcceptedWordCountDefaultsKey)

        self.permissionManager = permissionManager
        self.focusModel = focusModel
        self.inputMonitor = inputMonitor
        self.overlayController = overlayController
        self.suggestionInserter = suggestionInserter
        self.suggestionEngine = suggestionEngine
        self.suggestionSettings = suggestionSettings
        self.clipboardContextProvider = clipboardContextProvider
        self.clipboardRelevanceFilter = clipboardRelevanceFilter
        self.visualContextCoordinator = visualContextCoordinator
        self.writingMemoryStore = writingMemoryStore ?? WritingMemoryStore()
        self.recentFocusRing = recentFocusRing ?? RecentFocusRing()
        self.ambientScreenIndexer = ambientScreenIndexer ?? AmbientScreenIndexer()
        self.interactionState = interactionState
        self.workController = workController
        self.configuration = configuration
        self.spellChecker = spellChecker
        self.symSpellCorrector = symSpellCorrector
        self.spellingLanguageResolver = spellingLanguageResolver
        self.qualityMetricsStore = qualityMetricsStore
        self.userDefaults = userDefaults
        self.llamaRejectsPartialKVTrimsProvider = llamaRejectsPartialKVTrimsProvider
        settingsSnapshot = suggestionSettings.snapshot
        // These collaborators isolate "how overlay/logging works" from "when the coordinator
        // wants to show state," which keeps the coordinator closer to orchestration code.
        overlayPresenter = SuggestionOverlayPresenter(overlayController: overlayController)
        logger = SuggestionDebugLogger()
        totalTabAcceptedWordCount = max(storedTotalTabAcceptedWordCount, 0)
        visualContextStatus = visualContextCoordinator.status
        latestVisualContextText = visualContextCoordinator.latestExcerpt

        overlayState = overlayController.state

        focusModel.snapshotPublisher
            .sink { [weak self] snapshot in
                self?.handleFocusSnapshotChange(snapshot)
            }
            .store(in: &cancellables)

        permissionManager.inputMonitoringGrantedPublisher
            .sink { [weak self] _ in
                self?.handlePermissionChange()
            }
            .store(in: &cancellables)

        permissionManager.screenRecordingGrantedPublisher
            .sink { [weak self] _ in
                self?.handlePermissionChange()
                self?.syncAmbientScreenIndexer()
            }
            .store(in: &cancellables)

        // The monitor and overlay controller are callback-driven. The coordinator translates those
        // callbacks back into its state-machine methods.
        inputMonitor.onEvent = { [weak self] event in
            self?.handleInputEvent(event) ?? false
        }

        inputMonitor.onSuppressedSyntheticInput = { [weak self] in
            self?.handleSuppressedSyntheticInput()
        }

        // Fail-open preflight for the active accept tap. The tap should only route a matching key
        // into the coordinator while there is visible suggestion UI. We deliberately do not require
        // `.ready` or even an active session here: a background refresh can move `state`, and if the
        // session has gone stale the coordinator still needs one chance to hide the stale overlay
        // before the tap passes the original key through.
        inputMonitor.shouldConsumeAcceptKeyProvider = { [weak self] in
            guard let self else { return false }
            // Keep owning the accept key through the brief post-acceptance regeneration window too,
            // even though the overlay is hidden then. Otherwise a fast follow-up Tab in that gap
            // falls through to the host app as a real Tab and focus jumps out of the field — the
            // "rapid Tab breaks, slow Tab is fine" report. See `armPostExhaustionAcceptance`.
            guard self.overlayState.isVisible || self.postExhaustionAcceptanceState.isArmed else { return false }
            return true
        }

        overlayController.onStateChange = { [weak self] state in
            guard let self else { return }
            self.overlayState = state
            // Only sit in the synchronous keystroke critical path while a suggestion is actually
            // visible *and* accept-ready. With the overlay hidden, Cotabby observes via a
            // listen-only tap that does not gate event delivery to other apps (issue #328).
            // Streamed ghosts present while `state == .generating`; arming the accept `defaultTap`
            // for that whole decode held every keyDown on MainActor and ate / froze typing.
            switch state {
            case .visible:
                self.syncAcceptInterceptionForVisibleOverlay()
            case .hidden:
                self.cancelDeferredAcceptInterceptionArm()
                self.inputMonitor.setAcceptInterceptionActive(false)
                // A hidden overlay ends any post-exhaustion Tab-ownership window. Every teardown and
                // abort path hides the overlay, so ending the window here is the single catch-all
                // that returns the accept key to the host (and cancels the backstop timer) once the
                // window is genuinely over. The `.exhausted` accept re-arms *after* its own
                // `hideOverlay` call, so this never cancels a window that was just opened.
                self.clearPostExhaustionAcceptanceWindow()
            }
        }

        visualContextCoordinator.onStateChange = { [weak self] status, excerpt in
            self?.visualContextStatus = status
            self?.latestVisualContextText = excerpt
        }

        visualContextCoordinator.onInjectedContextReady = { [weak self] identity in
            self?.schedulePredictionForCurrentFocusIfPossible(matching: identity)
        }

        suggestionSettings.snapshotPublisher
            .dropFirst()
            .sink { [weak self] snapshot in
                self?.handleSuggestionSettingsChange(snapshot)
            }
            .store(in: &cancellables)

        // Align ambient indexing with the loaded settings / permission state once at construction.
        syncAmbientScreenIndexer()
    }

    /// Applies writing-memory + ambient-index toggles and Screen Recording to the background indexer.
    func syncAmbientScreenIndexer() {
        let ambientAllowed =
            settingsSnapshot.isAmbientScreenIndexEnabled
            && !settingsSnapshot.isFastModeEnabled
            && permissionManager.screenRecordingGranted
        ambientScreenIndexer.setScreenRecordingGranted(permissionManager.screenRecordingGranted)
        ambientScreenIndexer.setEnabled(ambientAllowed)
    }

    /// Builds retrieved screen + glossary context for the next request without awaiting OCR.
    /// When the ambient index is warm, embeds only the caret-prefix tip (cached) so
    /// `ContextualRetriever` can blend semantic similarity with lexical overlap.
    func retrievedPromptContext(
        for context: FocusedInputContext,
        prefixText: String
    ) -> RetrievedPromptContext {
        let fieldOCR = permissionManager.screenRecordingGranted
            ? visualContextCoordinator.excerpt(for: context)
            : nil
        let memory = settingsSnapshot.isWritingMemoryEnabled
            ? writingMemoryStore.snapshot()
            : .empty
        let ambientLines =
            settingsSnapshot.isAmbientScreenIndexEnabled && !settingsSnapshot.isFastModeEnabled
            ? ambientScreenIndexer.snapshot.lines
            : []
        // Query embedding is cheap (~ms) and skipped when there is nothing semantic to rank against.
        let queryEmbedding: [Float]? =
            ambientLines.contains(where: { $0.embedding != nil })
            ? TextSemanticEmbedder.shared.embedQuery(from: prefixText)
            : nil
        return ContextualRetriever.retrieve(
            prefixText: prefixText,
            fieldOCR: fieldOCR,
            ambientLines: ambientLines,
            memory: memory,
            recentFocus: recentFocusRing.snapshot(),
            currentBundleIdentifier: context.bundleIdentifier,
            queryEmbedding: queryEmbedding
        )
    }

    /// Records a focus surface into the recent-focus ring and nudges ambient refresh when useful.
    func recordFocusForRetrieval(_ snapshot: FocusSnapshot) {
        guard let context = snapshot.context else { return }
        recentFocusRing.record(
            applicationName: context.applicationName,
            bundleIdentifier: context.bundleIdentifier,
            windowTitle: context.windowTitle,
            focusedURLString: context.focusedURLString,
            ignoredBundleIdentifier: Bundle.main.bundleIdentifier
        )
        if settingsSnapshot.isAmbientScreenIndexEnabled,
           !settingsSnapshot.isFastModeEnabled,
           permissionManager.screenRecordingGranted {
            ambientScreenIndexer.requestRefresh(reason: "focus-change")
        }
    }

    /// Exposes the latest cancellation token for the split extension files.
    var currentWorkID: UInt64 {
        workController.currentWorkID
    }
}

/// AX state captured at keystroke time for the host-publish wait. Shared between the active poll
/// chain and the late-publish arm so a publish that arrives after the ceiling can still schedule
/// against the post-keystroke text instead of regenerating from a stale snapshot.
struct LateHostPublishBaseline {
    let precedingText: String?
    let elementIdentifier: String?
    let selectionLocation: Int?
    let selectionLength: Int?
    let keystrokeUptimeNanoseconds: UInt64
    let pollGeneration: UInt64
}
