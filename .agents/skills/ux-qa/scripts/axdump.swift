import AppKit
import ApplicationServices
import Foundation

// Reads an app's accessibility tree without sending any input.
//   axdump [AppName] [--json]   prints the tree; by default also lists the problems it can see by itself:
// interactive elements with no accessible name, click targets under 24 pt (WCAG 2.2 target size),
// elements poking out of their window, and interactive elements overlapping each other.
// Needs Accessibility permission for the terminal running it.

guard AXIsProcessTrusted() else {
    FileHandle.standardError.write(Data("Grant Accessibility to this terminal in System Settings › Privacy & Security.\n".utf8))
    exit(2)
}
let name = CommandLine.arguments.dropFirst().first { !$0.hasPrefix("--") } ?? "Shot"
let asJSON = CommandLine.arguments.contains("--json")
guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == name }) else {
    FileHandle.standardError.write(Data("\(name) is not running\n".utf8))
    exit(1)
}

struct Node {
    var depth: Int
    var role: String
    var name: String
    var value: String
    var frame: CGRect
    var enabled: Bool
    var window: Int
    var subrole = ""
    /// The system's close, minimise and zoom buttons, which the app doesn't draw.
    var isWindowControl: Bool { ["AXCloseButton", "AXMinimizeButton", "AXZoomButton", "AXFullScreenButton"].contains(subrole) }
}

func string(_ element: AXUIElement, _ key: String) -> String {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success, let value else { return "" }
    return (value as? String) ?? (value as? NSNumber)?.stringValue ?? ""
}

func frame(of element: AXUIElement) -> CGRect {
    var position: CFTypeRef?, size: CFTypeRef?
    var origin = CGPoint.zero, extent = CGSize.zero
    if AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &position) == .success, let position {
        AXValueGetValue(position as! AXValue, .cgPoint, &origin)
    }
    if AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &size) == .success, let size {
        AXValueGetValue(size as! AXValue, .cgSize, &extent)
    }
    return CGRect(origin: origin, size: extent)
}

func children(of element: AXUIElement) -> [AXUIElement] {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success else { return [] }
    return value as? [AXUIElement] ?? []
}

var nodes: [Node] = []
func walk(_ element: AXUIElement, depth: Int, window: Int) {
    let role = string(element, kAXRoleAttribute)
    let name = [kAXTitleAttribute, kAXDescriptionAttribute, "AXLabel"].map { string(element, $0) }.first { !$0.isEmpty } ?? ""
    nodes.append(Node(depth: depth, role: role, name: name, value: string(element, kAXValueAttribute), frame: frame(of: element), enabled: string(element, kAXEnabledAttribute) != "0", window: window, subrole: string(element, kAXSubroleAttribute)))
    for child in children(of: element) {
        walk(child, depth: depth + 1, window: window)
    }
}

let root = AXUIElementCreateApplication(app.processIdentifier)
for (index, window) in children(of: root).enumerated() where string(window, kAXRoleAttribute) == "AXWindow" {
    walk(window, depth: 0, window: index)
}

let interactive: Set<String> = ["AXButton", "AXCheckBox", "AXRadioButton", "AXSlider", "AXPopUpButton", "AXMenuButton", "AXTextField", "AXTextArea", "AXIncrementor", "AXComboBox"]
var problems: [String] = []
func describe(_ node: Node) -> String {
    "\(node.role) \"\(node.name)\" at \(Int(node.frame.minX)),\(Int(node.frame.minY)) \(Int(node.frame.width))×\(Int(node.frame.height))"
}
let windows = nodes.filter { $0.role == "AXWindow" }
for node in nodes where interactive.contains(node.role) && !node.isWindowControl {
    if node.name.isEmpty { problems.append("no accessible name: \(describe(node))") }
    if node.frame.width < 24 || node.frame.height < 24 { problems.append("target under 24 pt: \(describe(node))") }
    if let window = windows.first(where: { $0.window == node.window }), !window.frame.insetBy(dx: -1, dy: -1).contains(node.frame) {
        problems.append("outside its window: \(describe(node))")
    }
}
let controls = nodes.filter { interactive.contains($0.role) && $0.frame.width > 0 && !$0.isWindowControl }
for (index, first) in controls.enumerated() {
    for second in controls[(index + 1)...] where first.window == second.window && first.frame.intersection(second.frame).width > 2 && first.frame.intersection(second.frame).height > 2 {
        problems.append("overlap: \(describe(first)) and \(describe(second))")
    }
}

// Near misses are the usual alignment bug: two things meant to share a line that are a few points apart.
let visible = nodes.filter { $0.frame.width > 0 && $0.frame.height > 0 && ($0.role == "AXStaticText" || $0.role == "AXImage" || interactive.contains($0.role)) && !$0.isWindowControl }
for (index, first) in visible.enumerated() {
    for second in visible[(index + 1)...] where first.window == second.window {
        let overlap = min(first.frame.maxY, second.frame.maxY) - max(first.frame.minY, second.frame.minY)
        let centreOffset = abs(first.frame.midY - second.frame.midY)
        if overlap >= 0.5 * min(first.frame.height, second.frame.height), centreOffset > 0.5, centreOffset <= 6, first.frame.maxX <= second.frame.minX + 1 || second.frame.maxX <= first.frame.minX + 1 {
            problems.append("row near-miss, centres \(String(format: "%.1f", centreOffset)) pt apart: \(describe(first)) and \(describe(second))")
        }
        // Only things stacked right on top of each other are read as one column.
        let gap = max(second.frame.minY - first.frame.maxY, first.frame.minY - second.frame.maxY)
        let leftOffset = abs(first.frame.minX - second.frame.minX)
        if gap >= -1, gap <= 8, leftOffset > 0.5, leftOffset <= 4 {
            problems.append("left-edge near-miss, \(String(format: "%.1f", leftOffset)) pt apart: \(describe(first)) and \(describe(second))")
        }
    }
}

if asJSON {
    let rows = nodes.map { ["depth": $0.depth, "role": $0.role, "name": $0.name, "value": $0.value, "x": Int($0.frame.minX), "y": Int($0.frame.minY), "w": Int($0.frame.width), "h": Int($0.frame.height), "enabled": $0.enabled] as [String: Any] }
    let data = try JSONSerialization.data(withJSONObject: ["elements": rows, "problems": problems], options: [.prettyPrinted, .sortedKeys])
    print(String(decoding: data, as: UTF8.self))
} else {
    for node in nodes {
        print(String(repeating: "  ", count: node.depth) + describe(node) + (node.value.isEmpty ? "" : " = \(node.value)") + (node.enabled ? "" : " (disabled)"))
    }
    print("\n\(problems.count) problem(s)")
    problems.forEach { print("  - \($0)") }
}
