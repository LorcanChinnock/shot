import CoreGraphics
import Foundation

extension WindowInfo {
    /// Keeps normal-layer windows of other apps that are at least 40 × 40 pt.
    public static func parse(_ list: [[String: Any]], excludingPID: pid_t) -> [WindowInfo] {
        list.compactMap { entry in
            guard (entry[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let pid = (entry[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value, pid != excludingPID,
                  let number = (entry[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                  bounds.width >= 40, bounds.height >= 40
            else {
                return nil
            }
            return WindowInfo(
                windowID: number, frame: bounds, ownerPID: pid,
                ownerName: entry[kCGWindowOwnerName as String] as? String, title: entry[kCGWindowName as String] as? String
            )
        }
    }
}
