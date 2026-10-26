import Foundation

extension Gallery {
    /// How close to its original an "X (2)" has to be to be a second capture taken in the same second, which
    /// `FileNaming` also names that way, rather than a version saved from the editor.
    static let sameMomentWindow: TimeInterval = 2

    /// The newest capture in `items`, by date. An image saved again from the editor as "X (2).png" stands in for
    /// "X.png" and any earlier version beside it, dated by the newest of them, since the latest version has the markup.
    /// Recordings are never versions of one another.
    public static func latest(in items: [GalleryItem]) -> GalleryItem? {
        func key(_ item: GalleryItem, stem: String) -> String {
            item.url.deletingLastPathComponent().appendingPathComponent(stem).path + "." + item.url.pathExtension.lowercased()
        }
        var originals: [String: Date] = [:]
        for item in items where item.kind != .video {
            let (stem, version) = versioned(item.url.deletingPathExtension().lastPathComponent)
            if version == 1 {
                originals[key(item, stem: stem)] = item.date
            }
        }
        var newestInGroup: [String: (item: GalleryItem, version: Int, date: Date)] = [:]
        for item in items {
            let (stem, version) = versioned(item.url.deletingPathExtension().lastPathComponent)
            let original = originals[key(item, stem: stem)]
            let isSeparateCapture = item.kind == .video
                || version > 1 && original.map { abs(item.date.timeIntervalSince($0)) <= sameMomentWindow } == true
            let group = isSeparateCapture ? item.url.path : key(item, stem: stem)
            guard let current = newestInGroup[group] else {
                newestInGroup[group] = (item, version, item.date)
                continue
            }
            let date = max(current.date, item.date)
            newestInGroup[group] = version > current.version ? (item, version, date) : (current.item, current.version, date)
        }
        return newestInGroup.values
            .min { $0.date != $1.date ? $0.date > $1.date : $0.item.name < $1.item.name }?
            .item
    }

    /// "X (3)" is version 3 of "X"; anything else is version 1 of itself. The suffix is the one
    /// `VersionNaming.nextVersionURL` drops: a space, then digits in brackets.
    static func versioned(_ stem: String) -> (stem: String, version: Int) {
        guard stem.hasSuffix(")"), let open = stem.lastIndex(of: "("), open > stem.startIndex,
              stem[stem.index(before: open)] == " ",
              case let digits = stem[stem.index(after: open)..<stem.index(before: stem.endIndex)],
              !digits.isEmpty, digits.allSatisfy({ $0.isASCII && $0.isNumber }), let number = Int(digits)
        else {
            return (stem, 1)
        }
        return (String(stem[..<stem.index(before: open)]), max(number, 1))
    }
}
