import Foundation

extension Gallery {
    /// The save folder as the empty gallery and the Trash dialog name it: from the home folder ("Pictures/Shot"), or the
    /// whole path when it's elsewhere. `displayName` gives each folder's name as Finder shows it, such as "Bilder" in German.
    public static func folderPath(_ folder: URL, home: URL, displayName: (String) -> String = { ($0 as NSString).lastPathComponent }) -> String {
        let folderPath = folder.standardizedFileURL.path
        let homePath = home.standardizedFileURL.path
        guard folderPath != homePath else {
            return displayName(folderPath)
        }
        let prefix = homePath.hasSuffix("/") ? homePath : homePath + "/"
        guard folderPath.hasPrefix(prefix) else {
            return folderPath
        }
        var path = homePath
        var names: [String] = []
        for component in folderPath.dropFirst(prefix.count).split(separator: "/") {
            path += "/" + component
            names.append(displayName(path))
        }
        return names.joined(separator: "/")
    }

    /// How far each thumbnail in the Trash dialog is turned, in degrees, for `count` captures: one card for each of the
    /// first three, fanned left and right as on the board, and none for nothing.
    public static func trashFan(count: Int) -> [Double] {
        switch count {
        case ..<1: []
        case 1: [-3]
        case 2: [-6, 5]
        default: [-8, 0, 7]
        }
    }
}

extension KeyCombo {
    /// One label for each key to press, the modifiers first in the order macOS menus show them: ["⇧", "⌘", "4"].
    public var keycaps: [String] {
        var keys: [String] = []
        if modifiers & Self.control != 0 { keys.append("⌃") }
        if modifiers & Self.option != 0 { keys.append("⌥") }
        if modifiers & Self.shift != 0 { keys.append("⇧") }
        if modifiers & Self.command != 0 { keys.append("⌘") }
        return keys + [keyLabel]
    }
}
