import AppKit
import CoreGraphics
import Foundation

// Sends real mouse events in screen points (the same units as `session.sh shot`'s images and `axdump` frames).
//   input click X Y | dclick X Y | drag X1 Y1 X2 Y2 [shift] | scroll X Y DX DY
// Accessibility clicks don't reach custom-drawn views, so anything canvas-like needs these.
// It refuses to act unless the app under test is frontmost, so stolen focus can never click into another app.

let target = ProcessInfo.processInfo.environment["UXQA_APP"] ?? "Shot"
guard NSWorkspace.shared.frontmostApplication?.localizedName == target else {
    FileHandle.standardError.write(Data("refusing: \(target) is not frontmost\n".utf8))
    exit(3)
}

let args = CommandLine.arguments
func number(_ index: Int) -> Double {
    guard index < args.count, let value = Double(args[index]) else {
        FileHandle.standardError.write(Data("usage: input click|dclick|drag|scroll …\n".utf8))
        exit(2)
    }
    return value
}
func point(_ index: Int) -> CGPoint { CGPoint(x: number(index), y: number(index + 1)) }

func post(_ type: CGEventType, _ at: CGPoint, flags: CGEventFlags = [], clicks: Int64 = 1) {
    let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: at, mouseButton: .left)!
    event.flags = flags
    event.setIntegerValueField(.mouseEventClickState, value: clicks)
    event.post(tap: .cghidEventTap)
    usleep(30_000)
}

switch args.count > 1 ? args[1] : "" {
case "click":
    post(.mouseMoved, point(2)); post(.leftMouseDown, point(2)); post(.leftMouseUp, point(2))
case "dclick":
    post(.mouseMoved, point(2))
    for clicks: Int64 in [1, 2] {
        post(.leftMouseDown, point(2), clicks: clicks); post(.leftMouseUp, point(2), clicks: clicks)
    }
case "drag":
    let flags: CGEventFlags = args.count > 6 ? .maskShift : []
    let start = point(2), end = point(4)
    post(.mouseMoved, start, flags: flags); post(.leftMouseDown, start, flags: flags)
    for step in 1...20 {
        let t = Double(step) / 20
        post(.leftMouseDragged, CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t), flags: flags)
    }
    post(.leftMouseUp, end, flags: flags)
case "scroll":
    post(.mouseMoved, point(2))
    CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: Int32(number(5)), wheel2: Int32(number(4)), wheel3: 0)?.post(tap: .cghidEventTap)
default:
    FileHandle.standardError.write(Data("usage: input click|dclick|drag|scroll …\n".utf8))
    exit(2)
}
