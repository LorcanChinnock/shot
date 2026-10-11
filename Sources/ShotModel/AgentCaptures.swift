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

    /// How close to its original an "X (2)" has to be to be a second capture taken in the same second, which
    /// `FileNaming` also names that way, rather than a version saved from the editor.
    static let sameMomentWindow: TimeInterval = 2

    /// Newest first, by `date`. An image saved again from the editor as "X (2).png" stands in for "X.png" and any
    /// earlier version beside it, dated by the newest of them, since the latest version has the markup.
    public static func ranked(_ entries: [Entry], kind: Kind = .any) -> [Entry] {
        let matching = entries.filter(kind.matches)
        func key(_ entry: Entry, stem: String) -> String {
            entry.url.deletingLastPathComponent().appendingPathComponent(stem).path + "." + entry.url.pathExtension.lowercased()
        }
        var originals: [String: Date] = [:]
        for entry in matching where !entry.isVideo {
            let (stem, version) = versioned(entry.url.deletingPathExtension().lastPathComponent)
            if version == 1 {
                originals[key(entry, stem: stem)] = entry.date
            }
        }
        var newestInGroup: [String: (entry: Entry, version: Int, date: Date)] = [:]
        var order: [String] = []
        for entry in matching {
            let (stem, version) = versioned(entry.url.deletingPathExtension().lastPathComponent)
            let original = originals[key(entry, stem: stem)]
            let isSeparateCapture = entry.isVideo
                || version > 1 && original.map { abs(entry.date.timeIntervalSince($0)) <= sameMomentWindow } == true
            let group = isSeparateCapture ? entry.url.path : key(entry, stem: stem)
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

    /// The capture `query` names: a path or the exact file name, else, among the captures `ranked` gives, one whose
    /// name has every word of it, ignoring case and punctuation. The one with the most of the query's neighbouring
    /// words side by side wins, then the newest, so "shot 14.03" finds "Shot 2026-10-10 at 14.03.12.png" rather than
    /// a newer "Shot 2026-10-14 at 09.03.55.png".
    public static func named(_ query: String, in entries: [Entry]) -> Entry? {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return nil
        }
        let expanded = (query as NSString).expandingTildeInPath
        if let exact = entries.sorted(by: { $0.date > $1.date }).first(where: { $0.url.path == expanded || $0.name == query }) {
            return exact
        }
        let wanted = words(in: query)
        guard !wanted.isEmpty else {
            return nil
        }
        let pairs = zip(wanted, wanted.dropFirst()).map { [$0, $1] }
        var best: (entry: Entry, score: Int)?
        for entry in ranked(entries) {
            let name = words(in: entry.name)
            guard wanted.allSatisfy({ word in name.contains { $0.hasPrefix(word) } }) else {
                continue
            }
            let adjacent = zip(name, name.dropFirst()).map { [$0, $1] }
            let score = pairs.filter { pair in adjacent.contains { $0[0] == pair[0] && $0[1].hasPrefix(pair[1]) } }.count
            if score > best?.score ?? -1 {
                best = (entry, score)
            }
        }
        return best?.entry
    }

    /// When `text` says: an ISO 8601 date, or date and time, in `timeZone` unless it gives its own, or a span back from
    /// `now` such as "10m", "2h" or "3d".
    public static func date(since text: String, now: Date, timeZone: TimeZone = .current) -> Date? {
        let text = text.trimmingCharacters(in: .whitespaces).lowercased()
        let units: [Character: Double] = ["s": 1, "m": 60, "h": 3600, "d": 86400]
        if let unit = text.last.flatMap({ units[$0] }), let amount = Double(text.dropLast()), amount >= 0 {
            return now.addingTimeInterval(-amount * unit)
        }
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = timeZone
        let stamp = text.uppercased()
        guard stamp.contains("T") else {
            formatter.formatOptions = [.withFullDate]
            return formatter.date(from: stamp)
        }
        // "2026-10-10T14:03", without seconds, which agents often send, gets them added.
        let withSeconds = stamp.filter { $0 == ":" }.count == 1 && stamp.last?.isNumber == true ? stamp + ":00" : stamp
        let layouts: [ISO8601DateFormatter.Options] = [
            [.withInternetDateTime],
            [.withInternetDateTime, .withFractionalSeconds],
            [.withFullDate, .withTime, .withDashSeparatorInDate, .withColonSeparatorInTime],
        ]
        for layout in layouts {
            formatter.formatOptions = layout
            if let date = formatter.date(from: withSeconds) {
                return date
            }
        }
        return nil
    }

    /// "X (3)" is version 3 of "X"; anything else is version 1 of itself. The suffix is the one
    /// `FileNaming.nextVersionURL` drops: a space, then digits in brackets.
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

    /// The words of `text`, in lowercase, split at anything that isn't a letter or digit.
    private static func words(in text: String) -> [String] {
        text.lowercased().split { !($0.isLetter || $0.isNumber) }.map(String.init)
    }
}

extension AgentCaptures.Entry {
    fileprivate func with(date: Date) -> Self {
        var copy = self
        copy.date = date
        return copy
    }
}
