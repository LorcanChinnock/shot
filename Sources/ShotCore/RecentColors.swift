import Foundation

/// The custom colours picked lately in any colour editor, newest first, which the editor offers again as swatches.
public enum RecentColors {
    /// How many the editor keeps: one row of 26 pt swatches fits under its 200 pt field.
    public static let limit = 7

    /// `list` with `color` at the front. A colour already there, to the hex, moves to the front rather than showing twice,
    /// and a preset is left out, as it already has a swatch of its own.
    public static func adding(_ color: RGBA, to list: [RGBA]) -> [RGBA] {
        guard !RGBA.presets.contains(where: { $0.hex == color.hex }) else {
            return list
        }
        return Array(([color] + list.filter { $0.hex != color.hex }).prefix(limit))
    }

    /// The list stored as JSON, or empty when there's none or it can't be read.
    public static func decode(_ data: Data) -> [RGBA] {
        guard !data.isEmpty else {
            return []
        }
        return (try? JSONDecoder().decode([RGBA].self, from: data)) ?? []
    }

    public static func encode(_ list: [RGBA]) -> Data {
        (try? JSONEncoder().encode(list)) ?? Data()
    }
}
