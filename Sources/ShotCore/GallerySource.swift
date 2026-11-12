import Foundation

/// A row in the gallery's sidebar, which picks what the grid shows. One row is picked at a time, as in Finder; typing
/// `tag:name` in the search narrows any of them further.
public enum GallerySource: Hashable, Sendable {
    /// A kind of capture, in every folder: All Captures, Screenshots, Recordings or GIFs.
    case library(GalleryFilter)
    /// The captures directly in a folder, by path, or in the save folder itself when it's empty.
    case folder(String)
    /// The captures that carry a tag, whatever its case.
    case tag(String)

    public static let all = GallerySource.library(.all)

    /// The kind of capture the grid keeps.
    public var filter: GalleryFilter {
        if case let .library(filter) = self { filter } else { .all }
    }

    /// The folder the grid shows, or `nil` for every folder.
    public var folder: String? {
        if case let .folder(path) = self { path } else { nil }
    }

    /// The tags a capture needs to show.
    public var tags: Set<String> {
        if case let .tag(name) = self { [name] } else { [] }
    }
}

extension GalleryFilter {
    /// The filter's name in the sidebar's Library section.
    public var libraryTitle: String {
        switch self {
        case .all: String(localized: "All Captures")
        case .screenshots: String(localized: "Screenshots")
        case .videos: String(localized: "Recordings")
        case .gifs: String(localized: "GIFs")
        }
    }
}

/// How many captures each sidebar row shows, and how much room they take, counted once when the list or the tags change.
public struct GalleryCounts: Equatable, Sendable {
    public private(set) var library: [GalleryFilter: Int] = [:]
    /// The captures directly in each folder, by path, with the save folder itself as the empty path.
    public private(set) var folders: [String: Int] = [:]
    /// The captures carrying each tag, keyed by the tag in lower case.
    private var tagged: [String: Int] = [:]
    /// The size of every capture together, in bytes.
    public private(set) var bytes = 0

    public static let empty = GalleryCounts()

    private init() {}

    public init(_ items: [GalleryItem], tagsOf: [URL: [String]]) {
        for filter in GalleryFilter.allCases {
            library[filter] = 0
        }
        for item in items {
            for filter in GalleryFilter.allCases where filter.includes(item.kind) {
                library[filter, default: 0] += 1
            }
            folders[item.folder, default: 0] += 1
            bytes += item.bytes
            for tag in Set((tagsOf[item.url] ?? []).map { $0.lowercased() }) {
                tagged[tag, default: 0] += 1
            }
        }
    }

    /// How many captures carry `tag`, whatever its case.
    public func count(ofTag tag: String) -> Int {
        tagged[tag.lowercased()] ?? 0
    }

    /// How many captures `source` shows, before any search.
    public func count(of source: GallerySource) -> Int {
        switch source {
        case let .library(filter): library[filter] ?? 0
        case let .folder(path): folders[path] ?? 0
        case let .tag(name): count(ofTag: name)
        }
    }

    /// How much of a disk of `capacity` bytes the captures fill, from 0 to 1, or 0 when the capacity isn't known.
    public func share(ofCapacity capacity: Int?) -> Double {
        guard let capacity, capacity > 0 else {
            return 0
        }
        return min(1, Double(bytes) / Double(capacity))
    }
}
