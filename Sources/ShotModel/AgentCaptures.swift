import Foundation

/// Finds captures for an agent: the newest, a recent list, or one by a loosely typed name. Works on what the gallery
/// already lists, so it never reads a file.
public enum AgentCaptures {
    public struct Entry: Equatable, Sendable {
        public var url: URL
        public var isVideo: Bool
        public var date: Date

        public init(url: URL, isVideo: Bool, date: Date) {
            self.url = url
            self.isVideo = isVideo
            self.date = date
        }

        public var name: String { url.lastPathComponent }
    }

    public enum Kind: String, Sendable {
        case image, video, any

        /// Anything it doesn't know is `any`, so a slightly wrong argument still finds something.
        public init(lenient text: String?) {
            self = text.flatMap { Kind(rawValue: $0.trimmingCharacters(in: .whitespaces).lowercased()) } ?? .any
        }

        func matches(_ entry: Entry) -> Bool {
            switch self {
            case .image: !entry.isVideo
            case .video: entry.isVideo
            case .any: true
            }
        }
    }

    public static let defaultLimit = 10
    public static let maximumLimit = 50

    /// Newest first, by `date`. An image saved again from the editor as "X (2).png" stands in for "X.png" and any
    /// earlier version, dated by the newest of them, since the latest version has the markup. A capture named
    /// "X (2)" because another one took the same second counts as a version too; they're a second apart at most.
    public static func ranked(_ entries: [Entry], kind: Kind = .any) -> [Entry] {
        var newestInGroup: [String: (entry: Entry, version: Int, date: Date)] = [:]
        var order: [String] = []
        for entry in entries where kind.matches(entry) {
            let (stem, version) = versioned(entry.url.deletingPathExtension().lastPathComponent)
            let group = entry.isVideo ? entry.url.path : "\(stem).\(entry.url.pathExtension.lowercased())"
            guard let current = newestInGroup[group] else {
                newestInGroup[group] = (entry, version, entry.date)
                order.append(group)
                continue
            }
            let date = max(current.date, entry.date)
            newestInGroup[group] = version > current.version ? (entry, version, date) : (current.entry, current.version, date)
        }
        return order.compactMap { newestInGroup[$0] }
            .sorted { $0.date != $1.date ? $0.date > $1.date : $0.entry.name < $1.entry.name }
            .map { $0.entry.with(date: $0.date) }
    }

    public static func latest(_ entries: [Entry], kind: Kind) -> Entry? {
        ranked(entries, kind: kind).first
    }

    /// Up to `limit` (clamped to 1...50) captures from `since` on, newest first.
    public static func list(_ entries: [Entry], limit: Int?, since: Date?) -> [Entry] {
        let limit = min(max(limit ?? defaultLimit, 1), maximumLimit)
        return Array(ranked(entries).filter { entry in since.map { entry.date >= $0 } ?? true }.prefix(limit))
    }

    /// The capture `query` names: a path or the exact file name, else the newest whose name contains it, ignoring case,
    /// spaces and punctuation, so "shot 14.03" finds "Shot 2026-10-10 at 14.03.12.png".
    public static func named(_ query: String, in entries: [Entry]) -> Entry? {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return nil
        }
        let sorted = entries.sorted { $0.date > $1.date }
        let expanded = (query as NSString).expandingTildeInPath
        if let exact = sorted.first(where: { $0.url.path == expanded || $0.name == query }) {
            return exact
        }
        let words = folded(query).split(separator: " ")
        return sorted.first { entry in
            let name = folded(entry.name)
            return words.allSatisfy { name.contains($0) }
        }
    }

    /// When `text` says: an ISO 8601 date or date and time, or a span back from `now` such as "10m", "2h" or "3d".
    public static func date(since text: String, now: Date) -> Date? {
        let text = text.trimmingCharacters(in: .whitespaces).lowercased()
        let units: [Character: Double] = ["s": 1, "m": 60, "h": 3600, "d": 86400]
        if let unit = text.last.flatMap({ units[$0] }), let amount = Double(text.dropLast()), amount >= 0 {
            return now.addingTimeInterval(-amount * unit)
        }
        let full = ISO8601DateFormatter()
        if let date = full.date(from: text.uppercased()) {
            return date
        }
        let day = ISO8601DateFormatter()
        day.formatOptions = [.withFullDate]
        return day.date(from: text)
    }

    /// "X (3)" is version 3 of "X"; anything else is version 1 of itself.
    static func versioned(_ stem: String) -> (stem: String, version: Int) {
        guard stem.hasSuffix(")"), let open = stem.lastIndex(of: "("), open > stem.startIndex,
              stem[stem.index(before: open)] == " ",
              let number = Int(stem[stem.index(after: open)..<stem.index(before: stem.endIndex)]), number >= 2
        else {
            return (stem, 1)
        }
        return (String(stem[..<stem.index(before: open)]), number)
    }

    private static func folded(_ text: String) -> String {
        String(text.lowercased().map { $0.isLetter || $0.isNumber ? $0 : " " })
    }
}

extension AgentCaptures.Entry {
    fileprivate func with(date: Date) -> Self {
        var copy = self
        copy.date = date
        return copy
    }
}
