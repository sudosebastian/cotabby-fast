import Foundation

/// Classifies applications by browser family from their bundle identifier.
///
/// Two distinct questions live here on purpose:
///
/// - `isBrowser` is the broad "is the user typing in a web browser" check used for prompt tone
///   hints. It includes Safari and Firefox.
/// - `needsWebAccessibilityPriming` is the narrow "does this app hide its web text behind the
///   Chromium/Electron lazy-accessibility model" check that gates the expensive AX recovery paths
///   (renderer priming, cursor hit-testing, deeper candidate walks). It deliberately excludes
///   Safari/Firefox: WebKit builds its accessibility tree without an assistive client flipping a
///   flag, and Gecko does not use the Chromium text-marker model, so priming/hit-testing buys
///   nothing there and would only widen the blast radius.
///
/// Matching is by case-insensitive bundle-identifier prefix to tolerate channel suffixes
/// (`com.google.Chrome.canary`, `com.google.Chrome.beta`, etc.).
nonisolated enum BrowserAppDetector {
    /// Every browser family, used for the broad "typing in a browser" tone hint.
    private static let browserBundlePrefixes: [String] = [
        "com.apple.safari",
        "com.apple.safaritechnologypreview",
        "com.google.chrome",
        "org.mozilla.firefox",
        "company.thebrowser.browser",  // Arc
        "com.brave.browser",
        "com.microsoft.edgemac"
    ]

    /// Chromium-family browsers whose web content uses the lazy web-AX tree and opaque text-marker
    /// selection model. Safari/Firefox are intentionally absent (see type doc).
    private static let chromiumBundlePrefixes: [String] = [
        "com.google.chrome",
        "company.thebrowser.browser",  // Arc
        "com.brave.browser",
        "com.microsoft.edgemac"
    ]

    /// Electron apps (Chromium under the hood) whose focused text surfaces we intentionally cover.
    /// This is a named allowlist, not a blanket Electron opt-in: most Electron apps are not
    /// writing surfaces, and priming them wholesale risks unexpected behavior.
    ///
    /// Entries are lowercased and matched case-insensitively (see `isElectronEditor`). VS Code's
    /// real bundle id is the mixed-case `com.microsoft.VSCode`, so an exact match would silently
    /// miss it and leave the editor's entire Electron AX tree dormant.
    ///
    /// Chat clients (Slack/Discord/Teams) are included because their message composers are the
    /// writing surfaces users expect Cotabby in — without priming those trees stay empty and the
    /// app looks "disabled" even though it is not on the user blocklist.
    ///
    /// Cursor / Windsurf ship under opaque ToDesktop hashes (`com.todesktop.<hash>`) that change
    /// between builds; those are matched separately via `isToDesktopElectronTextSurface` using
    /// the application display name so unrelated ToDesktop apps are not primed.
    private static let electronEditorBundleIdentifiers: Set<String> = [
        "com.clickup.desktop-app",
        "com.microsoft.vscode",          // Visual Studio Code
        "com.microsoft.vscodeinsiders",  // VS Code - Insiders
        "com.vscodium",                  // VSCodium (FOSS VS Code build)
        "com.tinyspeck.slackmacgap",     // Slack
        "com.hnc.discord",               // Discord
        "com.microsoft.teams2",          // Microsoft Teams (new)
        "com.microsoft.teams",           // Microsoft Teams (legacy)
        "notion.id",                     // Notion
        "com.linear",                    // Linear
        "dev.zed.zed",                   // Zed
        "com.exafunction.windsurf"       // Windsurf (stable id when not ToDesktop)
    ]

    /// Display-name tokens that identify ToDesktop-packaged editors we cover. Compared
    /// case-insensitively against `NSRunningApplication.localizedName`.
    private static let toDesktopEditorApplicationNames: Set<String> = [
        "cursor",
        "windsurf"
    ]

    /// Broad check: is the user typing inside any web browser? Used for prompt tone hints.
    static func isBrowser(bundleIdentifier: String?) -> Bool {
        hasMatchingPrefix(bundleIdentifier, in: browserBundlePrefixes)
    }

    /// Narrow check: is this a Chromium-family browser (web content via lazy web-AX + text markers)?
    static func isChromiumBrowser(bundleIdentifier: String?) -> Bool {
        hasMatchingPrefix(bundleIdentifier, in: chromiumBundlePrefixes)
    }

    /// Is this a named Electron text surface we intentionally cover? Case-insensitive because
    /// macOS bundle ids are case-insensitive in practice and VS Code's is mixed-case.
    static func isElectronEditor(bundleIdentifier: String?) -> Bool {
        guard let lowered = bundleIdentifier?.lowercased() else { return false }
        return electronEditorBundleIdentifiers.contains(lowered)
    }

    /// Cursor/Windsurf (and similar) packaged by ToDesktop: bundle ids are opaque hashes under
    /// `com.todesktop.`, so the display name is the only durable identity. Requires both the
    /// ToDesktop prefix and a known editor name — a bare `com.todesktop.` match would prime
    /// unrelated ToDesktop apps.
    static func isToDesktopElectronTextSurface(
        bundleIdentifier: String?,
        applicationName: String?
    ) -> Bool {
        guard let bundle = bundleIdentifier?.lowercased(),
              bundle.hasPrefix("com.todesktop.")
        else {
            return false
        }
        guard let name = applicationName?.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
            !name.isEmpty
        else {
            return false
        }
        if toDesktopEditorApplicationNames.contains(name) {
            return true
        }
        // "Cursor Helper", "Cursor Nightly", etc.
        return toDesktopEditorApplicationNames.contains { name.hasPrefix($0 + " ") }
    }

    /// Gate for the Chromium/Electron-specific AX recovery paths (renderer priming, cursor
    /// hit-testing, deeper candidate walk). True only for apps that actually hide web text behind
    /// the lazy web-AX model. `applicationName` unlocks ToDesktop editor detection.
    static func needsWebAccessibilityPriming(
        bundleIdentifier: String?,
        applicationName: String? = nil
    ) -> Bool {
        isChromiumBrowser(bundleIdentifier: bundleIdentifier)
            || isElectronEditor(bundleIdentifier: bundleIdentifier)
            || isToDesktopElectronTextSurface(
                bundleIdentifier: bundleIdentifier,
                applicationName: applicationName
            )
    }

    private static func hasMatchingPrefix(_ bundleIdentifier: String?, in prefixes: [String]) -> Bool {
        guard let lower = bundleIdentifier?.lowercased() else { return false }
        return prefixes.contains { lower.hasPrefix($0) }
    }
}
