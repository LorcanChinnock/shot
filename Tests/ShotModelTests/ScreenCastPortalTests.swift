import Foundation
import Testing
@testable import ShotModel

@Test func screenCastPortalReadsTheStreamAndTokenStartAnswersWith() throws {
    let results: [String: BusValue] = [
        "streams": .array([.structure([.uint32(43), .dictionary([
            "source_type": .uint32(1), "position": .structure([.int32(1920), .int32(0)]), "size": .structure([.int32(960), .int32(540)]),
        ])])]),
        "restore_token": .string("412b113a-0d6c-4b1e-9e3f-2a5b8c7d6e1f"),
        "persist_mode": .uint32(2),
    ]
    let started = try ScreenCastPortal.started(response: 0, results: results)
    #expect(started == ScreenCastPortal.Started(
        stream: ScreenCastPortal.Stream(node: 43, position: CGPoint(x: 1920, y: 0), size: CGSize(width: 960, height: 540), sourceType: 1),
        restoreToken: "412b113a-0d6c-4b1e-9e3f-2a5b8c7d6e1f"
    ))

    // A portal may leave out where the source is, and the token, which an empty one is the same as.
    let bare = try ScreenCastPortal.started(response: 0, results: ["streams": .array([.structure([.uint32(7), .dictionary([:])])]), "restore_token": .string("")])
    #expect(bare == ScreenCastPortal.Started(stream: ScreenCastPortal.Stream(node: 7)))

    #expect(throws: ShotCommandError.io("The desktop portal started the screen cast but sent no stream to record.")) {
        try ScreenCastPortal.started(response: 0, results: ["streams": .array([])])
    }
    #expect(throws: ShotCommandError.noInput("The recording was cancelled or not allowed in the desktop's dialog, so nothing was recorded.")) {
        try ScreenCastPortal.started(response: 1, results: [:])
    }
    let failed = try #require(throws: ShotCommandError.self) { try ScreenCastPortal.started(response: 2, results: [:]) }
    #expect(failed.message.hasPrefix("The desktop portal couldn't record the screen."))
}

@Test func screenCastPortalReadsTheSessionAndProperties() throws {
    #expect(try ScreenCastPortal.sessionHandle(response: 0, results: ["session_handle": .string("/org/freedesktop/portal/desktop/session/1_42/shot_1")])
        == "/org/freedesktop/portal/desktop/session/1_42/shot_1")
    #expect(try ScreenCastPortal.sessionHandle(response: 0, results: ["session_handle": .objectPath("/s/1")]) == "/s/1")
    #expect(throws: ShotCommandError.io("The desktop portal started a screen cast but didn't say which.")) {
        try ScreenCastPortal.sessionHandle(response: 0, results: [:])
    }

    #expect(ScreenCastPortal.properties(["version": .uint32(5), "AvailableSourceTypes": .uint32(3), "AvailableCursorModes": .uint32(7)])
        == ScreenCastPortal.Properties(version: 5, sourceTypes: 3, cursorModes: 7))
    #expect(ScreenCastPortal.properties(["version": .uint32(1)]) == ScreenCastPortal.Properties(version: 1))
    #expect(ScreenCastPortal.properties([:]) == nil)
}

@Test func screenCastPortalMapsThePointerSettingOntoTheCursorModesItHas() {
    #expect(ScreenCastPortal.cursorMode(showsCursor: true, available: 7) == ScreenCastPortal.embeddedCursor)
    #expect(ScreenCastPortal.cursorMode(showsCursor: false, available: 7) == ScreenCastPortal.hiddenCursor)
    // Only the other is there, or neither, and metadata alone would leave Shot to draw the pointer itself.
    #expect(ScreenCastPortal.cursorMode(showsCursor: true, available: 1) == ScreenCastPortal.hiddenCursor)
    #expect(ScreenCastPortal.cursorMode(showsCursor: false, available: 2) == ScreenCastPortal.embeddedCursor)
    #expect(ScreenCastPortal.cursorMode(showsCursor: true, available: 4) == nil)
    #expect(ScreenCastPortal.cursorMode(showsCursor: true, available: 0) == nil)

    #expect(ScreenCastPortal.sourceTypes(window: true, available: 3) == ScreenCastPortal.window)
    #expect(ScreenCastPortal.sourceTypes(window: true, available: 1) == ScreenCastPortal.monitor)
    #expect(ScreenCastPortal.sourceTypes(window: false, available: 3) == ScreenCastPortal.monitor)
}

@Test func screenCastPortalKeepsAScreensPermissionAndRestoresItsToken() {
    #expect(ScreenCastPortal.selectOptions(types: 1, cursorMode: 2, persists: true, restoreToken: "abc") == [
        "types": .uint32(1), "multiple": .bool(false), "cursor_mode": .uint32(2), "persist_mode": .uint32(2), "restore_token": .string("abc"),
    ])
    #expect(ScreenCastPortal.selectOptions(types: 1, cursorMode: nil, persists: true, restoreToken: "") == [
        "types": .uint32(1), "multiple": .bool(false), "persist_mode": .uint32(2),
    ])
    // A window is picked every time, so its permission isn't kept and no token is sent.
    #expect(ScreenCastPortal.selectOptions(types: 2, cursorMode: 1, persists: false, restoreToken: "abc") == [
        "types": .uint32(2), "multiple": .bool(false), "cursor_mode": .uint32(1),
    ])

    // What xdg-desktop-portal answers a malformed token with, and what it doesn't.
    #expect(ScreenCastPortal.isTokenProblem(name: "org.freedesktop.portal.Error.InvalidArgument", message: "Restore token is not a valid UUID string"))
    #expect(!ScreenCastPortal.isTokenProblem(name: "org.freedesktop.portal.Error.InvalidArgument", message: "Invalid cursor mode"))
    #expect(!ScreenCastPortal.isTokenProblem(name: "org.freedesktop.portal.Error.NotAllowed", message: "Bad token"))
}

@Test func screenCastPortalSaysWhatWentWrongInPlainWords() {
    #expect(ScreenCastPortal.problem(name: "org.freedesktop.DBus.Error.ServiceUnknown", message: "").message.hasPrefix("The desktop portal isn't running, so Shot can't record on Wayland."))
    #expect(ScreenCastPortal.problem(name: "org.freedesktop.DBus.Error.InvalidArgs", message: "No such interface") == .unavailable(ScreenCastPortal.noBackend))
    #expect(ScreenCastPortal.problem(name: "org.freedesktop.portal.Error.NotAllowed", message: "Not allowed") == .noPermission("The desktop portal didn't allow the recording: Not allowed"))
    #expect(ScreenCastPortal.problem(name: "org.example.Odd", message: "") == .unavailable("The desktop portal couldn't record the screen: org.example.Odd"))
}

@Test func screenCastCropConvertsPointsToTheFramesPixels() {
    let monitor = ScreenCastPortal.Stream(node: 1, position: CGPoint(x: 1920, y: 0), size: CGSize(width: 960, height: 540))
    let frame = CGSize(width: 1920, height: 1080)
    // A monitor at a scale of 2, right of another: points on the desktop, less its position, twice over.
    #expect(ScreenCastPortal.crop(CGRect(x: 1930, y: 10, width: 100, height: 50), onDesktop: true, stream: monitor, frame: frame) == CGRect(x: 20, y: 20, width: 200, height: 100))
    // From the source's own top-left, as a picked window's rect is.
    #expect(ScreenCastPortal.crop(CGRect(x: 10, y: 10, width: 100, height: 50), onDesktop: false, stream: monitor, frame: frame) == CGRect(x: 20, y: 20, width: 200, height: 100))
    // The whole desktop, of which this monitor is a part, is all of its frame.
    #expect(ScreenCastPortal.crop(CGRect(x: 0, y: 0, width: 2880, height: 1080), onDesktop: true, stream: monitor, frame: frame) == CGRect(origin: .zero, size: frame))
    #expect(ScreenCastPortal.crop(nil, onDesktop: false, stream: monitor, frame: frame) == CGRect(origin: .zero, size: frame))
    // Off it, or less than 2 × 2 pixels on it.
    #expect(ScreenCastPortal.crop(CGRect(x: 0, y: 0, width: 100, height: 100), onDesktop: true, stream: monitor, frame: frame) == nil)
    #expect(ScreenCastPortal.crop(CGRect(x: 959.6, y: 0, width: 10, height: 10), onDesktop: false, stream: monitor, frame: frame) == nil)

    // Rounded out to whole pixels, then down to an even size, at a scale of 1.25, or with no size given, 1.
    let scaled = ScreenCastPortal.Stream(node: 1, size: CGSize(width: 1536, height: 864))
    #expect(ScreenCastPortal.crop(CGRect(x: 1, y: 1, width: 11, height: 11), onDesktop: true, stream: scaled, frame: frame) == CGRect(x: 1, y: 1, width: 14, height: 14))
    #expect(ScreenCastPortal.crop(CGRect(x: 0, y: 0, width: 1536, height: 864), onDesktop: true, stream: scaled, frame: frame) == CGRect(origin: .zero, size: frame))
    let odd = CGSize(width: 641, height: 361)
    #expect(ScreenCastPortal.crop(nil, onDesktop: false, stream: ScreenCastPortal.Stream(node: 1), frame: odd) == CGRect(x: 0, y: 0, width: 640, height: 360))
    #expect(ScreenCastPortal.crop(CGRect(x: 600, y: 0, width: 100, height: 20), onDesktop: true, stream: ScreenCastPortal.Stream(node: 1), frame: odd) == CGRect(x: 600, y: 0, width: 40, height: 20))
}

@Test func castFramePacksRowsAndScalesAnotherSizeIntoTheFirst() {
    // 3 × 2 pixels, each row padded to 16 bytes; each pixel's bytes are its column, row, 9 and 255.
    let padded: [UInt8] = (0 ..< 2).flatMap { y in (0 ..< 3).flatMap { x in [UInt8(x), UInt8(y), 9, 255] } + [0, 0, 0, 0] }
    let packed = padded.withUnsafeBytes { CastFrame.packed($0.baseAddress!, width: 3, height: 2, stride: 16, into: (3, 2)) }
    #expect([UInt8](packed) == (0 ..< 2).flatMap { y in (0 ..< 3).flatMap { x in [UInt8(x), UInt8(y), 9, 255] } })
    let tight = [UInt8](packed)
    #expect(tight.withUnsafeBytes { CastFrame.packed($0.baseAddress!, width: 3, height: 2, stride: 12, into: (3, 2)) } == packed)

    // Red and blue swapped, for a frame in the other order from the first.
    let swapped = tight.withUnsafeBytes { CastFrame.packed($0.baseAddress!, width: 3, height: 2, stride: 12, into: (3, 2), swapsRedAndBlue: true) }
    #expect([UInt8](swapped).prefix(8) == [9, 0, 0, 255, 9, 0, 1, 255])

    // Twice as big each way, then wider: kept in shape, nearest pixel, centred on black.
    let doubled = tight.withUnsafeBytes { CastFrame.packed($0.baseAddress!, width: 3, height: 2, stride: 12, into: (6, 4)) }
    #expect(doubled.count == 6 * 4 * 4)
    #expect([UInt8](doubled[0 ..< 4]) == [0, 0, 9, 255] && [UInt8](doubled[(3 * 6 + 5) * 4 ..< (3 * 6 + 6) * 4]) == [2, 1, 9, 255])
    let wide = tight.withUnsafeBytes { CastFrame.packed($0.baseAddress!, width: 3, height: 2, stride: 12, into: (5, 2)) }
    #expect([UInt8](wide[0 ..< 4]) == [0, 0, 0, 0] && [UInt8](wide[4 ..< 8]) == [0, 0, 9, 255] && [UInt8](wide[16 ..< 20]) == [0, 0, 0, 0])

    #expect(!CastFrame.isRedFirst(0) && !CastFrame.isRedFirst(1) && CastFrame.isRedFirst(2) && CastFrame.isRedFirst(3))
    #expect(FFmpeg.castPixelFormats == ["bgr0", "bgra", "rgb0", "rgba"])
}

@Test func ffmpegRecordsAScreenCastsRawFramesAtAConstantRate() {
    let arguments = FFmpeg.castArguments(
        size: CGSize(width: 1920, height: 1080), pixelFormat: "bgr0", crop: CGRect(x: 20, y: 40, width: 200, height: 100), frameRate: 30, limit: 610,
        output: "/tmp/0.mp4", version: "6.1.1"
    )
    #expect(arguments == [
        "-v", "error", "-nostdin", "-nostats", "-stats_period", "0.1", "-progress", "pipe:1", "-use_wallclock_as_timestamps", "1",
        "-f", "rawvideo", "-pix_fmt", "bgr0", "-video_size", "1920x1080", "-framerate", "30", "-i", "pipe:0", "-t", "610",
        "-vf", "crop=200:100:20:40,scale=out_color_matrix=bt709:out_range=tv", "-fps_mode", "cfr", "-r", "30",
        "-c:v", "libx264", "-preset", "veryfast", "-tune", "zerolatency", "-crf", "20", "-pix_fmt", "yuv420p",
        "-colorspace", "bt709", "-color_primaries", "bt709", "-color_trc", "bt709", "-color_range", "tv", "-movflags", "+faststart", "-f", "mp4", "-y", "/tmp/0.mp4",
    ])
    // ffmpeg before 5.1 spells the constant rate -vsync, and with no crop there's no crop filter.
    let old = FFmpeg.castArguments(size: CGSize(width: 320, height: 240), pixelFormat: "rgba", crop: nil, frameRate: 60, limit: 610, output: "/tmp/0.mp4", version: "4.4.1")
    #expect(old.contains("-vsync") && !old.contains("-fps_mode") && old[old.firstIndex(of: "-vf")! + 1] == "scale=out_color_matrix=bt709:out_range=tv")
}
