import Foundation

/// Whether Shot's windows follow the system appearance or keep to light or dark, from Settings › General. Captures,
/// annotations and exports look the same whichever it is.
public enum AppearanceMode: String, CaseIterable, Sendable {
    case system, light, dark
}
