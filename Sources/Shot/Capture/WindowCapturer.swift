import os
import ScreenCaptureKit
import ShotCoreApple

private let log = Logger.shot("capture")

enum WindowCapturer {
    struct Result: @unchecked Sendable {
        let image: CGImage
        let scale: CGFloat
    }

    /// Other apps' normal windows on screen, front to back. Their titles need the Screen Recording permission.
    static func onScreenWindows() -> [WindowInfo] {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return WindowInfo.parse(list, excludingPID: ProcessInfo.processInfo.processIdentifier)
    }

    /// Live capture of one window, so occluding windows do not appear.
    static func capture(windowID: CGWindowID, includeShadow: Bool) async throws -> Result {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
            throw CaptureError.windowNotFound
        }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let scale = CGFloat(filter.pointPixelScale)
        // At window size SCK shrinks the window to fit its shadow; pad, then trim the unused transparent space.
        let padding: CGFloat = includeShadow ? 150 : 0
        let config = SCStreamConfiguration()
        config.width = Int((filter.contentRect.width + padding * 2) * scale)
        config.height = Int((filter.contentRect.height + padding * 2) * scale)
        config.ignoreShadowsSingleWindow = !includeShadow
        config.showsCursor = false
        config.captureResolution = .best
        let captured: CGImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        let image = includeShadow ? ImageTrim.trimTransparentEdges(captured) : captured
        log.debug("Window \(windowID) frame \(window.frame.debugDescription, privacy: .public) contentRect \(filter.contentRect.debugDescription, privacy: .public) image \(image.width)x\(image.height)")
        return Result(image: image, scale: scale)
    }
}
