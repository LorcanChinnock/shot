import Foundation

/// A search typed in the gallery: words matched against names and text, and `tag:name` filters. A tag with spaces
/// is quoted, as in `tag:"Bug 42"`; a `tag:` with no name yet, while it's being typed, filters nothing.
public struct GalleryQuery: Equatable, Sendable {
    /// The words that aren't tags, joined by single spaces.
    public let text: String
    public let tags: [String]

    public init(_ query: String) {
        var words: [String] = []
        var tags: [String] = []
        var index = query.startIndex
        while index < query.endIndex {
            guard !query[index].isWhitespace else {
                index = query.index(after: index)
                continue
            }
            let start = index
            if query[start...].prefix(4).lowercased() == "tag:" {
                index = query.index(start, offsetBy: 4)
                var name = ""
                if index < query.endIndex, query[index] == "\"" {
                    index = query.index(after: index)
                    while index < query.endIndex, query[index] != "\"" {
                        name.append(query[index])
                        index = query.index(after: index)
                    }
                    if index < query.endIndex {
                        index = query.index(after: index)
                    }
                } else {
                    while index < query.endIndex, !query[index].isWhitespace {
                        name.append(query[index])
                        index = query.index(after: index)
                    }
                }
                let trimmed = name.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty {
                    tags.append(trimmed)
                }
            } else {
                while index < query.endIndex, !query[index].isWhitespace {
                    index = query.index(after: index)
                }
                words.append(String(query[start..<index]))
            }
        }
        text = words.joined(separator: " ")
        self.tags = tags
    }
}

/// Finder tags on captures. They live on the files themselves, so they show in Finder and Spotlight and follow a
/// file when it moves or is renamed, with nothing for Shot to keep in step. Like Finder, they ignore case.
public enum GalleryTags {
    /// How many of a set of files carry a tag.
    public enum Coverage: Equatable, Sendable {
        case none, some, all
    }

    /// The Finder tags on the file at `url`, as they are now.
    public static func tags(of url: URL) -> [String] {
        var url = url
        url.removeCachedResourceValue(forKey: .tagNamesKey)
        return (try? url.resourceValues(forKeys: [.tagNamesKey]).tagNames) ?? []
    }

    /// Replaces the Finder tags on the file at `url` with `tags`.
    public static func setTags(_ tags: [String], of url: URL) throws {
        try (url as NSURL).setResourceValue(tags, forKey: .tagNamesKey)
    }

    /// Whether `tags` holds `tag`, ignoring case.
    public static func has(_ tags: [String], _ tag: String) -> Bool {
        tags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame }
    }

    /// Whether `tags` holds every one of `required`.
    public static func has(_ tags: [String], all required: [String]) -> Bool {
        required.allSatisfy { has(tags, $0) }
    }

    /// Every tag in `tagsOf`, once each whatever its case, in Finder's order.
    public static func all(_ tagsOf: [URL: [String]]) -> [String] {
        var seen: Set<String> = []
        var names: [String] = []
        for tags in tagsOf.values {
            for tag in tags where seen.insert(tag.lowercased()).inserted {
                names.append(tag)
            }
        }
        return names.sorted { a, b in
            let order = a.localizedStandardCompare(b)
            return order == .orderedSame ? a < b : order == .orderedAscending
        }
    }

    /// How many of `files` carry `tag`.
    public static func coverage(of tag: String, on files: [URL], tagsOf: [URL: [String]]) -> Coverage {
        let count = files.filter { has(tagsOf[$0] ?? [], tag) }.count
        return count == 0 ? .none : count == files.count ? .all : .some
    }

    /// `tags` with `tag` added at the end, unless it's already there.
    public static func adding(_ tag: String, to tags: [String]) -> [String] {
        has(tags, tag) ? tags : tags + [tag]
    }

    /// `tags` without `tag`, in any case.
    public static func removing(_ tag: String, from tags: [String]) -> [String] {
        tags.filter { $0.caseInsensitiveCompare(tag) != .orderedSame }
    }

    /// `typed` as a tag's name: trimmed, with newlines turned to spaces since Finder keeps a tag's colour after one, and
    /// `nil` when nothing is left.
    public static func tagName(_ typed: String) -> String? {
        let name = typed.components(separatedBy: .newlines).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }

    /// `tags` with `old` called `new` in place, or just without `old` when `new` is there already.
    public static func renaming(_ old: String, to new: String, in tags: [String]) -> [String] {
        guard has(tags, old) else {
            return tags
        }
        let others = removing(old, from: tags)
        return has(others, new) ? others : tags.map { $0.caseInsensitiveCompare(old) == .orderedSame ? new : $0 }
    }

    /// The tags each of the files in `tagsOf` that carry `old` gets when it's renamed to `new`, or removed when `new` is
    /// `nil`. Only the files that change are returned.
    public static func renaming(_ old: String, to new: String?, tagsOf: [URL: [String]]) -> [URL: [String]] {
        var changed: [URL: [String]] = [:]
        for (file, tags) in tagsOf where has(tags, old) {
            let next = new.map { renaming(old, to: $0, in: tags) } ?? removing(old, from: tags)
            if next != tags {
                changed[file] = next
            }
        }
        return changed
    }

    /// The tags each of `files` gets when `tag` is clicked in the Tag menu: removed from all of them when every one
    /// carries it, otherwise added to those that don't. Only the files that change are returned.
    public static func toggling(_ tag: String, on files: [URL], tagsOf: [URL: [String]]) -> [URL: [String]] {
        let remove = coverage(of: tag, on: files, tagsOf: tagsOf) == .all
        var changed: [URL: [String]] = [:]
        for file in files {
            let current = tagsOf[file] ?? []
            let next = remove ? removing(tag, from: current) : adding(tag, to: current)
            if next != current {
                changed[file] = next
            }
        }
        return changed
    }
}
