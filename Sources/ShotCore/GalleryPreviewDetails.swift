import CoreGraphics
import Foundation

/// The other versions of a capture in its folder: the file it was saved from and the edits saved beside it, which
/// `VersionNaming` names "a.png", "a (2).png", "a (3).png".
public struct GalleryVersions: Equatable, Sendable {
    /// Whether the original is still in the folder.
    public let hasOriginal: Bool
    /// How many edits were saved from it.
    public let edits: Int

    public init(hasOriginal: Bool, edits: Int) {
        self.hasOriginal = hasOriginal
        self.edits = edits
    }

    /// "Original + 2 edits", or "2 edits" once the original has gone.
    public var label: String {
        hasOriginal ? String(localized: "Original + \(edits) edits") : String(localized: "\(edits) edits")
    }
}

/// What the preview's details panel says about a capture.
extension Gallery {
    /// The versions of `item` among `items`, or `nil` when it's the only one.
    public static func versions(of item: GalleryItem, in items: [GalleryItem]) -> GalleryVersions? {
        let original = VersionNaming.originalName(of: item.url)
        let folder = item.url.deletingLastPathComponent().standardizedFileURL
        let family = items.filter {
            $0.kind == item.kind && VersionNaming.originalName(of: $0.url) == original
                && $0.url.deletingLastPathComponent().standardizedFileURL == folder
        }
        guard family.count > 1 else {
            return nil
        }
        let hasOriginal = family.contains { $0.name == original }
        return GalleryVersions(hasOriginal: hasOriginal, edits: family.count - (hasOriginal ? 1 : 0))
    }

    /// When the capture was taken, as "Today, 21:53" or a date and time.
    public static func takenLabel(_ date: Date, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter.string(from: date)
    }

    /// The image's size in pixels, when it's known, and the file's size: "1,040 × 600 · 214 KB".
    public static func sizeLabel(pixels: CGSize?, bytes: Int, locale: Locale = .current) -> String {
        let file = bytes.formatted(.byteCount(style: .file).locale(locale))
        guard let pixels, pixels.width > 0, pixels.height > 0 else {
            return file
        }
        let width = Int(pixels.width).formatted(.number.locale(locale)), height = Int(pixels.height).formatted(.number.locale(locale))
        return "\(width) × \(height) · \(file)"
    }

    /// The folder a capture is in, from the save folder: "Shot › Clients › Acme".
    public static func folderLabel(_ folder: String, rootName: String) -> String {
        ([rootName] + folder.split(separator: "/").map(String.init)).joined(separator: " › ")
    }

    /// The index `by` steps from `index` among `count` items, or `nil` past either end.
    public static func stepped(from index: Int, by step: Int, count: Int) -> Int? {
        let next = index + step
        return (0..<count).contains(next) ? next : nil
    }
}

extension TextSearch {
    /// Where `query` appears in `text`, ignoring case and accents as search does, in order and without overlapping.
    public static func ranges(of query: String, in text: String) -> [Range<String.Index>] {
        let wanted = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !wanted.isEmpty else {
            return []
        }
        var ranges: [Range<String.Index>] = []
        var start = text.startIndex
        while start < text.endIndex, let found = text.range(of: wanted, options: [.caseInsensitive, .diacriticInsensitive], range: start..<text.endIndex) {
            ranges.append(found)
            start = found.upperBound
        }
        return ranges
    }
}

extension CaptureText {
    /// Where `query` appears in the image, in its pixels: one box for each match, around the words it touches, or around its
    /// line when the line has no word boxes.
    public func boxes(matching query: String) -> [CGRect] {
        lines.flatMap { line -> [CGRect] in
            let words = Line.wordRanges(in: line.text)
            return TextSearch.ranges(of: query, in: line.text).map { match in
                let touched = zip(words, line.words).filter { range, _ in range.overlaps(match) }.map(\.1.box)
                return touched.isEmpty ? line.box : touched.dropFirst().reduce(touched[0]) { $0.union($1) }
            }
        }
    }
}
