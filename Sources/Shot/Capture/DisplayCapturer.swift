import AppKit
import ScreenCaptureKit
import ShotCore

struct FrozenDisplay: @unchecked Sendable {
    let displayID: CGDirectDisplayID
    /// AppKit global frame in points.
    let frame: CGRect
    let scale: CGFloat
    let image: CGImage
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    static var underPointer: NSScreen? {
        let location = NSEvent.mouseLocation
        return screens.first { NSMouseInRect(location, $0.frame, false) } ?? main
    }
}

enum CaptureError: LocalizedError {
    case displayNotFound
    case windowNotFound
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .displayNotFound: "Display not found"
        case .windowNotFound: "Window not found"
        case .encodingFailed: "Could not encode image"
        }
    }
}

/// SCK filter and configuration are not `Sendable`; each job is used by exactly one task.
struct CaptureJob: @unchecked Sendable {
    let filter: SCContentFilter
    let config: SCStreamConfiguration
}

@MainActor
enum DisplayCapturer {
    private struct Target: Sendable {
        let displayID: CGDirectDisplayID
        let frame: CGRect
        let backingScale: CGFloat
    }

    /// Captures every display (or only `screens`) concurrently.
    static func captureAll(screens: [NSScreen] = NSScreen.screens) async throws -> [FrozenDisplay] {
        let targets = screens.map { Target(displayID: $0.displayID, frame: $0.frame, backingScale: $0.backingScaleFactor) }
        let prefs = Preferences()
        return try await capture(targets, showsCursor: prefs.captureShowsCursor, hidesShotUI: prefs.captureHidesShotUI)
    }

    private nonisolated static func capture(_ targets: [Target], showsCursor: Bool, hidesShotUI: Bool) async throws -> [FrozenDisplay] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        return try await withThrowingTaskGroup(of: FrozenDisplay.self) { group in
            for target in targets {
                guard let display = content.displays.first(where: { $0.displayID == target.displayID }) else {
                    throw CaptureError.displayNotFound
                }
                let ownApps = content.applications.filter { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
                let filter = hidesShotUI
                    ? SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
                    : SCContentFilter(display: display, excludingWindows: [])
                let config = SCStreamConfiguration()
                config.width = Int(target.frame.width * target.backingScale)
                config.height = Int(target.frame.height * target.backingScale)
                config.showsCursor = showsCursor
                config.captureResolution = .best
                let job = CaptureJob(filter: filter, config: config)
                group.addTask {
                    let image = try await SCScreenshotManager.captureImage(contentFilter: job.filter, configuration: job.config)
                    return FrozenDisplay(displayID: target.displayID, frame: target.frame, scale: CGFloat(image.width) / target.frame.width, image: image)
                }
            }
            var results: [FrozenDisplay] = []
            for try await frozen in group {
                results.append(frozen)
            }
            return results
        }
    }
}
