import AppKit

@MainActor
final class QuickAccessController {
    static let shared = QuickAccessController()

    func add(fileURL: URL, thumbnail: CGImage, scale: CGFloat) {
        Toast.show("Saved \(fileURL.lastPathComponent)")
    }
}
