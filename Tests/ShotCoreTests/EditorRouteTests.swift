import Foundation
import Testing
@testable import ShotCore

@Test func annotateRoutesByFileType() {
    #expect(EditorRoute(host: "annotate", path: "/tmp/a.png") == .image(URL(fileURLWithPath: "/tmp/a.png")))
    #expect(EditorRoute(host: "annotate", path: "/tmp/a.mp4") == .video(URL(fileURLWithPath: "/tmp/a.mp4")))
    #expect(EditorRoute(host: "annotate", path: "/tmp/a.MOV") == .video(URL(fileURLWithPath: "/tmp/a.MOV")))
    #expect(EditorRoute(fileURL: URL(fileURLWithPath: "/tmp/b.m4v")) == .video(URL(fileURLWithPath: "/tmp/b.m4v")))
    #expect(EditorRoute(fileURL: URL(fileURLWithPath: "/tmp/b.jpg")) == .image(URL(fileURLWithPath: "/tmp/b.jpg")))
}

@Test func editVideoAlwaysOpensTheVideoEditor() {
    #expect(EditorRoute(host: "edit-video", path: "/tmp/a.mp4") == .video(URL(fileURLWithPath: "/tmp/a.mp4")))
    #expect(EditorRoute(host: "edit-video", path: "/tmp/a.png") == .video(URL(fileURLWithPath: "/tmp/a.png")))
}

@Test func routeExpandsTildeAndRejectsMissingPaths() {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    #expect(EditorRoute(host: "annotate", path: "~/x.png") == .image(URL(fileURLWithPath: home).appendingPathComponent("x.png")))
    #expect(EditorRoute(host: "annotate", path: nil) == nil)
    #expect(EditorRoute(host: "edit-video", path: "") == nil)
    #expect(EditorRoute(host: "capture-area", path: "/tmp/a.png") == nil)
    #expect(EditorRoute.hosts == ["annotate", "edit-video"])
}
