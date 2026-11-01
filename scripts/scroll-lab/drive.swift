import CoreGraphics
import Foundation
// drive drag x1 y1 x2 y2 | key <code> | move x y | scroll x y <px> <events> <ms> | flick x y <startPx> <decay> <frames> <ms>
let a = CommandLine.arguments
func post(_ e: CGEvent?) { e?.post(tap: .cghidEventTap) }
func mouse(_ type: CGEventType, _ x: Double, _ y: Double) { post(CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: CGPoint(x: x, y: y), mouseButton: .left)) }
func wheel(_ px: Int32) { post(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: -px, wheel2: 0, wheel3: 0)) }
switch a[1] {
case "move": CGWarpMouseCursorPosition(CGPoint(x: Double(a[2])!, y: Double(a[3])!))
case "key":
    let code = CGKeyCode(a[2])!
    post(CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true)); usleep(40000); post(CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false))
case "drag":
    let p = a[2...5].map { Double($0)! }
    mouse(.mouseMoved, p[0], p[1]); usleep(150000); mouse(.leftMouseDown, p[0], p[1]); usleep(100000)
    for i in 1...20 { let t = Double(i) / 20; mouse(.leftMouseDragged, p[0] + (p[2] - p[0]) * t, p[1] + (p[3] - p[1]) * t); usleep(20000) }
    usleep(100000); mouse(.leftMouseUp, p[2], p[3])
case "scroll":
    CGWarpMouseCursorPosition(CGPoint(x: Double(a[2])!, y: Double(a[3])!)); usleep(100000)
    for _ in 0..<Int(a[5])! { wheel(Int32(a[4])!); usleep(UInt32(a[6])! * 1000) }
case "flick":
    CGWarpMouseCursorPosition(CGPoint(x: Double(a[2])!, y: Double(a[3])!)); usleep(100000)
    var v = Double(a[4])!; let decay = Double(a[5])!
    for _ in 0..<Int(a[6])! { wheel(Int32(v.rounded())); v *= decay; usleep(UInt32(a[7])! * 1000) }
default: break
}
