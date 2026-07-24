import AppKit
import CoreGraphics
import Foundation
import Logging
import ScreenCaptureKit

/// File overview:
/// Captures full attached displays via ScreenCaptureKit for the ambient screen index. Distinct from
/// `WindowScreenshotService`, which crops around the focused field for precise once-per-focus OCR.
///
/// Full-display capture is intentionally coarser and parallelized by the caller. This type only
/// owns the SCK display filter + scale math so Visual stays the single screenshot boundary.

struct CapturedDisplayScreenshot: @unchecked Sendable {
    let image: CGImage
    let displayID: CGDirectDisplayID
}

enum DisplayScreenshotError: LocalizedError {
    case screenRecordingPermissionMissing
    case noDisplays
    case captureFailed(String)

    var errorDescription: String? {
        switch self {
        case .screenRecordingPermissionMissing:
            return "Screen Recording permission is required to capture display context."
        case .noDisplays:
            return "No shareable displays were available for capture."
        case let .captureFailed(message):
            return "Unable to capture display screenshot: \(message)"
        }
    }
}

struct DisplayScreenshotService {
    /// Maximum long-edge pixels for ambient captures. Lower than the field-crop path so Vision
    /// `.fast` stays cheap across multiple Retina displays.
    var maxImageDimension: Int = 900

    /// Captures every on-screen display in parallel. Failures on individual displays are skipped so
    /// one bad monitor does not abort the whole ambient refresh.
    func captureAllDisplays() async throws -> [CapturedDisplayScreenshot] {
        guard CGPreflightScreenCaptureAccess() else {
            throw DisplayScreenshotError.screenRecordingPermissionMissing
        }

        let content = try await currentShareableContent()
        let displays = content.displays
        guard !displays.isEmpty else {
            throw DisplayScreenshotError.noDisplays
        }

        return await withTaskGroup(of: CapturedDisplayScreenshot?.self) { group in
            for display in displays {
                group.addTask {
                    do {
                        return try await self.captureDisplay(display)
                    } catch {
                        CotabbyLogger.app.debug(
                            "Ambient display capture failed display=\(display.displayID) reason=\(error.localizedDescription)"
                        )
                        return nil
                    }
                }
            }

            var results: [CapturedDisplayScreenshot] = []
            for await captured in group {
                if let captured {
                    results.append(captured)
                }
            }
            return results
        }
    }

    private func captureDisplay(_ display: SCDisplay) async throws -> CapturedDisplayScreenshot {
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let scale = backingScaleFactor(for: display)
        let rawWidth = CGFloat(display.width)
        let rawHeight = CGFloat(display.height)
        let longest = max(rawWidth, rawHeight) * scale
        let outputScale: CGFloat
        if longest > CGFloat(maxImageDimension) {
            outputScale = CGFloat(maxImageDimension) / max(rawWidth, rawHeight)
        } else {
            outputScale = scale
        }

        let configuration = SCStreamConfiguration()
        configuration.width = max(Int((rawWidth * outputScale).rounded(.up)), 1)
        configuration.height = max(Int((rawHeight * outputScale).rounded(.up)), 1)
        configuration.showsCursor = false
        configuration.scalesToFit = true

        let image = try await captureImage(filter: filter, configuration: configuration)
        return CapturedDisplayScreenshot(image: image, displayID: display.displayID)
    }

    private func backingScaleFactor(for display: SCDisplay) -> CGFloat {
        let displayID = CGDirectDisplayID(display.displayID)
        if let screen = NSScreen.screens.first(where: {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?
                .uint32Value == displayID
        }) {
            return screen.backingScaleFactor
        }
        return NSScreen.main?.backingScaleFactor ?? 2.0
    }

    private func currentShareableContent() async throws -> SCShareableContent {
        try await withCheckedThrowingContinuation { continuation in
            SCShareableContent.getExcludingDesktopWindows(true, onScreenWindowsOnly: true) { content, error in
                if let error {
                    continuation.resume(throwing: DisplayScreenshotError.captureFailed(error.localizedDescription))
                    return
                }
                guard let content else {
                    continuation.resume(throwing: DisplayScreenshotError.captureFailed("Shareable content was unavailable."))
                    return
                }
                continuation.resume(returning: content)
            }
        }
    }

    private func captureImage(
        filter: SCContentFilter,
        configuration: SCStreamConfiguration
    ) async throws -> CGImage {
        try await withCheckedThrowingContinuation { continuation in
            SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration) { image, error in
                if let error {
                    continuation.resume(throwing: DisplayScreenshotError.captureFailed(error.localizedDescription))
                    return
                }
                guard let image else {
                    continuation.resume(throwing: DisplayScreenshotError.captureFailed("ScreenCaptureKit returned no image."))
                    return
                }
                continuation.resume(returning: image)
            }
        }
    }
}
