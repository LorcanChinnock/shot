import os
import ScreenCaptureKit

private let log = Logger(subsystem: "dev.lorcan.Shot", category: "capture")

enum WindowCapturer {
    struct Result: @unchecked Sendable {
        let image: CGImage
        let scale: CGFloat
    }

    /// Live capture of one window, so occluding windows do not appear.
    static func capture(windowID: CGWindowID, includeShadow: Bool) async throws -> Result {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
            throw CaptureError.windowNotFound
        }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let scale = CGFloat(filter.pointPixelScale)
        let config = SCStreamConfiguration()
        config.width = Int(filter.contentRect.width * scale)
        config.height = Int(filter.contentRect.height * scale)
        config.ignoreShadowsSingleWindow = !includeShadow
        config.showsCursor = false
        config.captureResolution = .best
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        log.notice("Window \(windowID) frame \(window.frame.debugDescription, privacy: .public) contentRect \(filter.contentRect.debugDescription, privacy: .public) image \(image.width)x\(image.height)")
        return Result(image: image, scale: scale)
    }
}
