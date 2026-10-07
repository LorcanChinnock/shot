import Foundation
import UniformTypeIdentifiers

public enum GalleryKind: String, Sendable {
    case image, video, gif

    public init?(fileExtension: String) {
        guard let type = UTType(filenameExtension: fileExtension) else {
            return nil
        }
        if type.conforms(to: .gif) {
            self = .gif
        } else if type.conforms(to: .movie) {
            self = .video
        } else if type.conforms(to: .image) {
            self = .image
        } else {
            return nil
        }
    }

    /// GIFs are shown but have no editor.
    public var isEditable: Bool { self != .gif }
}

public struct GalleryItem: Identifiable, Hashable, Sendable {
    public let url: URL
    public let kind: GalleryKind
    public let date: Date
    public let bytes: Int

    public var id: URL { url }
    public var name: String { url.lastPathComponent }

    public init(url: URL, kind: GalleryKind, date: Date, bytes: Int) {
        self.url = url
        self.kind = kind
        self.date = date
        self.bytes = bytes
    }
}

public enum GalleryFilter: String, CaseIterable, Sendable {
    case all, screenshots, videos, gifs

    public var title: String {
        switch self {
        case .all: "All"
        case .screenshots: "Screenshots"
        case .videos: "Videos"
        case .gifs: "GIFs"
        }
    }

    func includes(_ kind: GalleryKind) -> Bool {
        switch self {
        case .all: true
        case .screenshots: kind == .image
        case .videos: kind == .video
        case .gifs: kind == .gif
        }
    }
}

public enum GallerySort: String, CaseIterable, Sendable {
    case newest, oldest, name, size

    public var title: String {
        switch self {
        case .newest: "Newest first"
        case .oldest: "Oldest first"
        case .name: "Name"
        case .size: "Largest first"
        }
    }

    /// Only date sorts are grouped by day.
    public var isByDate: Bool { self == .newest || self == .oldest }
}

public struct GallerySection: Identifiable, Equatable, Sendable {
    public let title: String
    public let items: [GalleryItem]

    public var id: String { title }
}

public enum Gallery {
    public static let tileSizes: ClosedRange<Double> = 120...320
    public static let defaultTileSize: Double = 190

    /// The screenshots, recordings and GIFs directly inside `folder`; hidden files and other types are skipped.
    public static func items(in folder: URL, fileManager: FileManager = .default) -> [GalleryItem] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .creationDateKey, .fileSizeKey, .isRegularFileKey]
        let urls = (try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []
        return urls.compactMap { url in
            guard let kind = GalleryKind(fileExtension: url.pathExtension),
                  let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true else {
                return nil
            }
            return GalleryItem(url: url, kind: kind, date: values.creationDate ?? values.contentModificationDate ?? .distantPast, bytes: values.fileSize ?? 0)
        }
    }

    public static func visible(_ items: [GalleryItem], filter: GalleryFilter, sort: GallerySort, query: String) -> [GalleryItem] {
        let query = query.trimmingCharacters(in: .whitespaces)
        let matching = items.filter { item in
            filter.includes(item.kind) && (query.isEmpty || item.name.localizedStandardContains(query))
        }
        return matching.sorted { a, b in
            switch sort {
            case .newest: a.date != b.date ? a.date > b.date : a.name < b.name
            case .oldest: a.date != b.date ? a.date < b.date : a.name < b.name
            case .name: a.name.localizedStandardCompare(b.name) == .orderedAscending
            case .size: a.bytes != b.bytes ? a.bytes > b.bytes : a.name < b.name
            }
        }
    }

    /// Day buckets for a date-sorted list: Today, Yesterday, This Week, This Month, then each older month.
    /// Any other order is one untitled section.
    public static func sections(_ items: [GalleryItem], sort: GallerySort, now: Date = Date(), calendar: Calendar = .current) -> [GallerySection] {
        guard sort.isByDate else {
            return items.isEmpty ? [] : [GallerySection(title: "", items: items)]
        }
        var order: [String] = []
        var buckets: [String: [GalleryItem]] = [:]
        for item in items {
            let title = bucketTitle(for: item.date, now: now, calendar: calendar)
            if buckets[title] == nil {
                order.append(title)
            }
            buckets[title, default: []].append(item)
        }
        return order.map { GallerySection(title: $0, items: buckets[$0] ?? []) }
    }

    private static func bucketTitle(for date: Date, now: Date, calendar: Calendar) -> String {
        if calendar.isDate(date, inSameDayAs: now) {
            return "Today"
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        if calendar.isDate(date, equalTo: now, toGranularity: .weekOfYear) {
            return "This Week"
        }
        if calendar.isDate(date, equalTo: now, toGranularity: .month) {
            return "This Month"
        }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date)
    }

    /// `name` with the original extension kept and path separators and edge spaces removed; nil when nothing is left.
    public static func renamedURL(of url: URL, to name: String) -> URL? {
        var base = name.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        let ext = url.pathExtension
        if !ext.isEmpty, base.lowercased().hasSuffix("." + ext.lowercased()) {
            base = String(base.dropLast(ext.count + 1))
        }
        guard !base.isEmpty, !base.hasPrefix(".") else {
            return nil
        }
        return url.deletingLastPathComponent().appendingPathComponent(base).appendingPathExtension(ext)
    }

    /// Moves trashed files back to where they were and returns the originals it restored; one whose old path is taken again stays in the Trash.
    public static func restore(_ moves: [(trashed: URL, original: URL)]) -> [URL] {
        let manager = FileManager.default
        return moves.compactMap { move in
            guard !manager.fileExists(atPath: move.original.path), (try? manager.moveItem(at: move.trashed, to: move.original)) != nil else {
                return nil
            }
            return move.original
        }
    }

    /// `selection` with `url` added, or removed when it was already there.
    public static func toggled(_ selection: Set<URL>, _ url: URL) -> Set<URL> {
        selection.symmetricDifference([url])
    }

    /// Whether every one of `visible` is selected; false when there is nothing to select.
    public static func allSelected(_ selection: Set<URL>, in visible: [GalleryItem]) -> Bool {
        !visible.isEmpty && visible.allSatisfy { selection.contains($0.url) }
    }

    /// Edit applies only when it can open every item: none are GIFs.
    public static func canEdit(_ items: [GalleryItem]) -> Bool {
        !items.isEmpty && items.allSatisfy(\.kind.isEditable)
    }

    /// The next item to select after an arrow key, clamped to the ends.
    public static func moved(from index: Int?, by step: Int, count: Int) -> Int? {
        guard count > 0 else {
            return nil
        }
        guard let index else {
            return step > 0 ? 0 : count - 1
        }
        return min(max(index + step, 0), count - 1)
    }

    /// The item one grid row up or down from `index`, where `sectionSizes` are the item counts of the stacked sections
    /// and each section starts a new row. Moving past the first or last row stays put; a short last row lands on its final item.
    public static func movedVertically(from index: Int?, sectionSizes: [Int], down: Bool, columns: Int) -> Int? {
        let total = sectionSizes.reduce(0, +)
        guard total > 0, columns > 0 else {
            return nil
        }
        guard let index else {
            return down ? 0 : total - 1
        }
        var start = 0
        var section = 0
        while section < sectionSizes.count - 1, index >= start + sectionSizes[section] {
            start += sectionSizes[section]
            section += 1
        }
        let size = sectionSizes[section]
        let offset = index - start
        let column = offset % columns
        if down {
            if offset / columns < (size - 1) / columns {
                return start + min(offset + columns, size - 1)
            }
            guard section + 1 < sectionSizes.count else {
                return index
            }
            let nextSize = sectionSizes[section + 1]
            return start + size + min(column, nextSize - 1)
        }
        if offset >= columns {
            return index - columns
        }
        guard section > 0 else {
            return index
        }
        let previousSize = sectionSizes[section - 1]
        let previousStart = start - previousSize
        return previousStart + min((previousSize - 1) / columns * columns + column, previousSize - 1)
    }

    public static func duration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let hours = total / 3600, minutes = total / 60 % 60, secs = total % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, secs) : String(format: "%d:%02d", minutes, secs)
    }
}
