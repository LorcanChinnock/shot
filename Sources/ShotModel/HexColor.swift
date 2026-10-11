import Foundation

/// sRGB colours as hex strings, such as `#1E90FF`.
public enum HexColor {
    /// `#RRGGBB` in capitals, with `AA` added only when the colour isn't opaque. Components are clamped to 0...1.
    public static func string(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat = 1) -> String {
        let bytes = [red, green, blue, alpha].map { Int((min(max($0, 0), 1) * 255).rounded()) }
        let shown = bytes[3] == 255 ? bytes.prefix(3) : bytes[...]
        return "#" + shown.map { String(format: "%02X", $0) }.joined()
    }

    /// Reads `#RGB`, `#RRGGBB` or `#RRGGBBAA`, with or without the `#`, in either case. `nil` for anything else.
    public static func components(_ hex: String) -> (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat)? {
        var digits = Substring(hex.trimmingCharacters(in: .whitespaces))
        if digits.first == "#" {
            digits = digits.dropFirst()
        }
        guard [3, 6, 8].contains(digits.count), digits.allSatisfy(\.isHexDigit) else {
            return nil
        }
        if digits.count == 3 {
            digits = Substring(digits.flatMap { [$0, $0] })
        }
        var bytes: [CGFloat] = []
        var rest = digits
        while !rest.isEmpty {
            bytes.append(CGFloat(UInt8(rest.prefix(2), radix: 16)!) / 255)
            rest = rest.dropFirst(2)
        }
        return (bytes[0], bytes[1], bytes[2], bytes.count == 4 ? bytes[3] : 1)
    }
}
