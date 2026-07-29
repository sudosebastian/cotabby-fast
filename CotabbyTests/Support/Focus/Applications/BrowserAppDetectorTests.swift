import XCTest
@testable import Cotabby

/// Verifies `BrowserAppDetector`'s two distinct classifications: the broad `isBrowser` used for
/// prompt tone hints, and the narrow `needsWebAccessibilityPriming` that gates the Chromium/Electron
/// AX recovery paths. The split matters: Safari/Firefox are browsers but must NOT trigger priming
/// or hit-testing.
final class BrowserAppDetectorTests: XCTestCase {
    func testIsBrowserCoversAllFamiliesIncludingSafariAndFirefox() {
        XCTAssertTrue(BrowserAppDetector.isBrowser(bundleIdentifier: "com.google.Chrome"))
        XCTAssertTrue(BrowserAppDetector.isBrowser(bundleIdentifier: "com.apple.Safari"))
        XCTAssertTrue(BrowserAppDetector.isBrowser(bundleIdentifier: "org.mozilla.firefox"))
        XCTAssertTrue(BrowserAppDetector.isBrowser(bundleIdentifier: "com.brave.Browser"))
        XCTAssertTrue(BrowserAppDetector.isBrowser(bundleIdentifier: "company.thebrowser.Browser"))
        XCTAssertFalse(BrowserAppDetector.isBrowser(bundleIdentifier: "com.apple.Terminal"))
        XCTAssertFalse(BrowserAppDetector.isBrowser(bundleIdentifier: nil))
    }

    func testMatchingIsCaseInsensitiveAndPrefixBased() {
        // Channel suffixes (canary/beta) and case variations still match the family prefix.
        XCTAssertTrue(BrowserAppDetector.isChromiumBrowser(bundleIdentifier: "com.google.Chrome.canary"))
        XCTAssertTrue(BrowserAppDetector.isChromiumBrowser(bundleIdentifier: "COM.GOOGLE.CHROME"))
    }

    func testChromiumExcludesSafariAndFirefox() {
        XCTAssertTrue(BrowserAppDetector.isChromiumBrowser(bundleIdentifier: "com.google.Chrome"))
        XCTAssertTrue(BrowserAppDetector.isChromiumBrowser(bundleIdentifier: "com.microsoft.edgemac"))
        XCTAssertTrue(BrowserAppDetector.isChromiumBrowser(bundleIdentifier: "com.brave.Browser"))
        XCTAssertFalse(BrowserAppDetector.isChromiumBrowser(bundleIdentifier: "com.apple.Safari"))
        XCTAssertFalse(BrowserAppDetector.isChromiumBrowser(bundleIdentifier: "org.mozilla.firefox"))
    }

    func testElectronEditorAllowlist() {
        XCTAssertTrue(BrowserAppDetector.isElectronEditor(bundleIdentifier: "com.clickup.desktop-app"))
        // VS Code ships under the mixed-case `com.microsoft.VSCode`; matching must be case-insensitive
        // or its entire Electron AX tree stays dormant and no suggestions ever resolve.
        XCTAssertTrue(BrowserAppDetector.isElectronEditor(bundleIdentifier: "com.microsoft.VSCode"))
        XCTAssertTrue(BrowserAppDetector.isElectronEditor(bundleIdentifier: "com.microsoft.VSCodeInsiders"))
        XCTAssertTrue(BrowserAppDetector.isElectronEditor(bundleIdentifier: "com.vscodium"))
        // Chat composers are writing surfaces users expect Cotabby in; without priming their trees
        // stay empty and the app looks disabled despite not being on the user blocklist.
        XCTAssertTrue(BrowserAppDetector.isElectronEditor(bundleIdentifier: "com.hnc.Discord"))
        XCTAssertTrue(BrowserAppDetector.isElectronEditor(bundleIdentifier: "com.tinyspeck.slackmacgap"))
        XCTAssertTrue(BrowserAppDetector.isElectronEditor(bundleIdentifier: "notion.id"))
        // Electron, but not a text-editing surface we cover: must stay out of the priming allowlist.
        XCTAssertFalse(BrowserAppDetector.isElectronEditor(bundleIdentifier: "com.spotify.client"))
        XCTAssertFalse(BrowserAppDetector.isElectronEditor(bundleIdentifier: nil))
    }

    func testToDesktopEditorRequiresKnownDisplayName() {
        XCTAssertTrue(
            BrowserAppDetector.isToDesktopElectronTextSurface(
                bundleIdentifier: "com.todesktop.230313mzl4w4u92",
                applicationName: "Cursor"
            )
        )
        XCTAssertTrue(
            BrowserAppDetector.isToDesktopElectronTextSurface(
                bundleIdentifier: "com.todesktop.abcdef",
                applicationName: "Cursor Nightly"
            )
        )
        // Bare ToDesktop prefix must not prime unrelated apps.
        XCTAssertFalse(
            BrowserAppDetector.isToDesktopElectronTextSurface(
                bundleIdentifier: "com.todesktop.abcdef",
                applicationName: "Some Other App"
            )
        )
        XCTAssertFalse(
            BrowserAppDetector.isToDesktopElectronTextSurface(
                bundleIdentifier: "com.todesktop.abcdef",
                applicationName: nil
            )
        )
    }

    func testNeedsPrimingForChromiumAndElectronOnly() {
        XCTAssertTrue(
            BrowserAppDetector.needsWebAccessibilityPriming(bundleIdentifier: "com.google.Chrome"))
        XCTAssertTrue(
            BrowserAppDetector.needsWebAccessibilityPriming(bundleIdentifier: "com.clickup.desktop-app"))
        XCTAssertTrue(
            BrowserAppDetector.needsWebAccessibilityPriming(bundleIdentifier: "com.microsoft.VSCode"))
        XCTAssertTrue(
            BrowserAppDetector.needsWebAccessibilityPriming(bundleIdentifier: "com.hnc.Discord"))
        XCTAssertTrue(
            BrowserAppDetector.needsWebAccessibilityPriming(
                bundleIdentifier: "com.todesktop.230313mzl4w4u92",
                applicationName: "Cursor"
            )
        )
        XCTAssertFalse(
            BrowserAppDetector.needsWebAccessibilityPriming(
                bundleIdentifier: "com.todesktop.230313mzl4w4u92",
                applicationName: "Not Cursor"
            )
        )
        XCTAssertFalse(
            BrowserAppDetector.needsWebAccessibilityPriming(bundleIdentifier: "com.apple.Safari"))
        XCTAssertFalse(
            BrowserAppDetector.needsWebAccessibilityPriming(bundleIdentifier: "org.mozilla.firefox"))
        XCTAssertFalse(
            BrowserAppDetector.needsWebAccessibilityPriming(bundleIdentifier: nil))
    }
}
