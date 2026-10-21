import Foundation

/// The text the user reads for `value`, in their language. Every string ShotCore shows goes through here rather than
/// `String(localized:)`, which Linux doesn't have. The build still extracts the literal into the catalog, because it
/// finds strings by their `String.LocalizationValue` type rather than by the call.
public func shotLocalized(_ value: String.LocalizationValue) -> String {
    String(localized: value)
}
