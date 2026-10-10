import AppKit
import SwiftUI

/// Acme Support: a made-up support and analytics app for a made-up shop, built only to be screenshotted.
///
///     swift run ShotDemo --scene ticket,chat --appearance light
///
/// `--scene` takes `ticket`, `dashboard` and `chat`, comma-separated; each opens its own window, laid out
/// left to right and centred on the main screen. `--appearance light|dark` overrides the system appearance.
/// `--area x,y,w,h` centres the windows in that rectangle instead (screen points, from the top left), to line them
/// up with a capture region. `--backdrop` puts a plain backdrop behind the windows, so captures show no wallpaper or other apps.
/// ⌘R replays the animations.
@main
@MainActor
enum DemoMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate(options: Options(CommandLine.arguments))
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }
}

enum Scene: String, CaseIterable {
    case ticket, dashboard, chat

    var size: CGSize { self == .chat ? CGSize(width: 380, height: 600) : CGSize(width: 960, height: 600) }

    var title: String {
        switch self {
        case .ticket: "Ticket #4821"
        case .dashboard: "Reports"
        case .chat: "#checkout"
        }
    }
}

struct Options {
    var scenes: [Scene] = [.ticket]
    var appearance: NSAppearance.Name?
    var backdrop = false
    var area: CGRect?

    init(_ arguments: [String]) {
        var rest = arguments.dropFirst()
        while let flag = rest.popFirst() {
            if flag == "--backdrop" {
                backdrop = true
                continue
            }
            let value = rest.popFirst() ?? ""
            switch flag {
            case "--scene":
                scenes = value.split(separator: ",").compactMap { Scene(rawValue: String($0)) }
                if scenes.isEmpty { scenes = [.ticket] }
            case "--area":
                let n = value.split(separator: ",").compactMap { Double($0) }
                if n.count == 4 { area = CGRect(x: n[0], y: n[1], width: n[2], height: n[3]) }
            case "--appearance":
                appearance = value == "dark" ? .darkAqua : value == "light" ? .aqua : nil
            default:
                FileHandle.standardError.write(Data("ignoring \(flag)\n".utf8))
            }
        }
    }
}

/// Bumped by ⌘R; scene roots use it as their identity, so every on-appear animation runs again.
@MainActor @Observable final class Replay {
    var count = 0
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let options: Options
    let replay = Replay()
    var windows: [NSWindow] = []

    init(options: Options) {
        self.options = options
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let name = options.appearance { NSApp.appearance = NSAppearance(named: name) }
        NSApp.mainMenu = makeMenu()
        if options.backdrop, let screen = NSScreen.main { windows.append(makeBackdrop(screen)) }

        // Lay the windows out side by side, the group centred, so every launch puts them in the same place.
        let gap: CGFloat = 24
        var screen = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        if let area = options.area, let full = NSScreen.main?.frame {
            screen = CGRect(x: area.minX, y: full.maxY - area.maxY, width: area.width, height: area.height)
        }
        let total = options.scenes.map(\.size.width).reduce(0, +) + gap * CGFloat(options.scenes.count - 1)
        var x = (screen.midX - total / 2).rounded()
        for scene in options.scenes {
            let window = makeWindow(scene)
            window.setFrameOrigin(CGPoint(x: x, y: (screen.midY - scene.size.height / 2).rounded()))
            window.makeKeyAndOrderFront(nil)
            windows.append(window)
            x += scene.size.width + gap
        }
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    private func makeWindow(_ scene: Scene) -> NSWindow {
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: scene.size),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Acme Support – \(scene.title)"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: SceneRoot(scene: scene, replay: replay))
        host.sizingOptions = []  // The window's size is fixed; don't let SwiftUI manage its limits.
        window.contentView = host
        return window
    }

    /// A borderless window at the back of this app's own windows. Bringing the demo forward brings it too, so it hides
    /// every other app's windows as well as the wallpaper.
    private func makeBackdrop(_ screen: NSScreen) -> NSWindow {
        let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.collectionBehavior = [.ignoresCycle]
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: Backdrop())
        host.sizingOptions = []
        window.contentView = host
        window.orderFront(nil)
        return window
    }

    private func makeMenu() -> NSMenu {
        let main = NSMenu()
        func submenu(_ title: String, _ items: [NSMenuItem]) {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.submenu = NSMenu(title: title)
            items.forEach { item.submenu?.addItem($0) }
            main.addItem(item)
        }
        let replayItem = NSMenuItem(title: "Replay Animations", action: #selector(replayAnimations), keyEquivalent: "r")
        replayItem.target = self
        submenu("Acme", [NSMenuItem(title: "Quit Acme Support", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")])
        submenu("Edit", [
            NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"),
            NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"),
            NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"),
        ])
        submenu("View", [replayItem])
        return main
    }

    @objc private func replayAnimations() {
        replay.count += 1
    }
}

struct SceneRoot: View {
    let scene: Scene
    let replay: Replay

    var body: some View {
        Group {
            switch scene {
            case .ticket: TicketScene()
            case .dashboard: DashboardScene()
            case .chat: ChatScene()
            }
        }
        .id(replay.count)
        .frame(width: scene.size.width, height: scene.size.height)
        .background(.background)
    }
}

struct Backdrop: View {
    var body: some View {
        LinearGradient(colors: [Color(red: 0.86, green: 0.90, blue: 0.95), Color(red: 0.93, green: 0.90, blue: 0.95)], startPoint: .topLeading, endPoint: .bottomTrailing)
            .ignoresSafeArea()
    }
}
