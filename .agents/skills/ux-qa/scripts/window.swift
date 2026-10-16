import CoreGraphics
import Foundation

// Finds the app's windows, so `screencapture -l ID` can capture one without bringing it to the front. "On screen" means
// ordered in, so a window covered by other apps still counts.
//   window          ID X Y W H of the app's frontmost normal window, in screen points
//   window --all    every on-screen window of the app, front to back: ID X Y W H layer title (toasts and panels sit above layer 0)

let target = ProcessInfo.processInfo.environment["UXQA_APP"] ?? "Shot"
let all = CommandLine.arguments.contains("--all")
let windows = (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []).filter {
    $0[kCGWindowOwnerName as String] as? String == target && (all || $0[kCGWindowLayer as String] as? Int == 0)
}
var found = false
for info in windows {
    guard let id = info[kCGWindowNumber as String] as? Int,
          let boundsInfo = info[kCGWindowBounds as String] as? NSDictionary,
          let bounds = CGRect(dictionaryRepresentation: boundsInfo), bounds.width > 1, bounds.height > 1 else { continue }
    var line = "\(id) \(Int(bounds.minX)) \(Int(bounds.minY)) \(Int(bounds.width)) \(Int(bounds.height))"
    if all { line += " \(info[kCGWindowLayer as String] as? Int ?? 0) \(info[kCGWindowName as String] as? String ?? "")" }
    print(line)
    found = true
    if !all { break }
}
if !found {
    FileHandle.standardError.write(Data("no window of \(target) found\n".utf8))
    exit(1)
}
