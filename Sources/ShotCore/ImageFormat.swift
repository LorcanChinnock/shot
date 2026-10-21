import Foundation

public enum ImageFormat: String, CaseIterable, Sendable {
    case png, jpeg

    public var fileExtension: String { self == .png ? "png" : "jpg" }

    public init(fileExtension: String) {
        self = ["jpg", "jpeg"].contains(fileExtension.lowercased()) ? .jpeg : .png
    }
}
