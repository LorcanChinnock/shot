import AppKit
import ApplicationServices
import ShotCore

/// Finds where a browser window shows its page, through the Accessibility API. Needs the Accessibility permission.
enum BrowserPageFinder {
    private static let maxDepth = 25
    private static let messagingTimeout: Float = 0.3

    /// Whether `pid` is an app macOS lists as able to open web links. Electron apps such as Slack show web content too,
    /// but are not browsers.
    private static func isBrowser(pid: pid_t) -> Bool {
        guard let bundle = NSRunningApplication(processIdentifier: pid)?.bundleURL?.standardizedFileURL,
              let probe = URL(string: "https://example.com") else {
            return false
        }
        return NSWorkspace.shared.urlsForApplications(toOpen: probe).contains { $0.standardizedFileURL == bundle }
    }

    /// The page's rect in CoreGraphics global space, or nil when the window has none (not a browser). Callers check Accessibility first.
    static func page(of window: WindowInfo) -> CGRect? {
        guard isBrowser(pid: window.ownerPID) else {
            return nil
        }
        let app = AXUIElementCreateApplication(window.ownerPID)
        AXUIElementSetMessagingTimeout(app, messagingTimeout)
        // Chromium builds its accessibility tree only when asked.
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        guard let axWindow = axWindows(of: app).first(where: { frame(of: $0).map { matches($0, window.frame) } ?? false }) else {
            return nil
        }
        var webAreas: [CGRect] = []
        collectWebAreas(in: axWindow, depth: 0, into: &webAreas)
        return BrowserPage.page(among: webAreas, inside: window.frame)
    }

    private static func matches(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) < 2 && abs(a.minY - b.minY) < 2 && abs(a.width - b.width) < 2 && abs(a.height - b.height) < 2
    }

    private static func axWindows(of app: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success else {
            return []
        }
        return value as? [AXUIElement] ?? []
    }

    private static func collectWebAreas(in element: AXUIElement, depth: Int, into areas: inout [CGRect]) {
        if string(kAXRoleAttribute, of: element) == "AXWebArea" {
            if let rect = frame(of: element) {
                areas.append(rect)
            }
            return
        }
        guard depth < maxDepth else {
            return
        }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success,
              let children = value as? [AXUIElement] else {
            return
        }
        for child in children {
            collectWebAreas(in: child, depth: depth + 1, into: &areas)
        }
    }

    private static func string(_ attribute: String, of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        var position: CFTypeRef?
        var size: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &position) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &size) == .success,
              let position, let size else {
            return nil
        }
        var origin = CGPoint.zero
        var extent = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &origin), AXValueGetValue(size as! AXValue, .cgSize, &extent) else {
            return nil
        }
        return CGRect(origin: origin, size: extent)
    }
}
