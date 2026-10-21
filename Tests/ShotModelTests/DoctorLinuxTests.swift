import Foundation
import Testing
@testable import ShotModel

private func facts(
    session: String? = "wayland", agentCapture: Bool = true, listening: Bool = false, status: Result<[String: JSONValue], ShotCommandError>? = nil,
    folderExists: Bool = true, folderError: String? = nil, colorEmoji: Bool = true, screenshotPortal: Result<Int, ShotCommandError>? = nil,
    ffmpeg: Doctor.FFmpegFacts? = nil
) -> Doctor.LinuxFacts {
    Doctor.LinuxFacts(
        version: "0.7.0", settingsFile: "/home/me/.config/dev.lorcan.Shot.plist", sessionType: session, agentCapture: agentCapture,
        socketPath: "/home/me/.local/share/dev.lorcan.Shot/agent.sock", listening: listening, status: status, folder: "/home/me/Pictures/Shot",
        folderExists: folderExists, folderError: folderError, captures: 1, colorEmoji: colorEmoji,
        screenshotPortal: screenshotPortal, ffmpeg: ffmpeg
    )
}

/// What `shot serve` answers a status request with, from `capturer`, which can't do what `limits` say.
private func serving(version: String = "0.7.0", capturer: String = "x11", limits: [String: JSONValue] = [:]) -> Result<[String: JSONValue], ShotCommandError> {
    .success(["capturing": .bool(false), "recording": .null, "version": .string(version), "capturer": .string(capturer), "limits": .object(limits)])
}

@Test func doctorOnLinuxSaysWhatRunsSoFarAndWhatNeedsAMac() {
    let json = Doctor.json(Doctor.checks(facts()))
    #expect(json == .object([
        "ok": .bool(true),
        "checks": .array([
            .object([
                "name": .string("platform"), "outcome": .string("pass"),
                "detail": .string("Shot 0.7.0 on Linux, reading its settings from /home/me/.config/dev.lorcan.Shot.plist. The session is Wayland."),
            ]),
            .object([
                "name": .string("letAgentsCaptureAndRecord"), "outcome": .string("pass"),
                "detail": .string("Let agents capture and record is on."),
            ]),
            .object([
                "name": .string("serve"), "outcome": .string("pass"),
                "detail": .string("shot serve isn't running. shot capture, shot windows and the MCP tools that capture start it when they need it."),
            ]),
            .object([
                "name": .string("notOnLinuxYet"), "outcome": .string("warn"),
                "detail": .string(
                    "Recording, picking and video aren't on Linux yet: shot record, pick, gif, trim and frames, info and edit on a video, and the MCP tools record_window, ask_for_capture, get_frames, make_gif, trim_video and edit_video answer that they're not on Linux yet. The image commands and the tools that read and edit screenshots work, and shot capture, shot windows and the MCP tools that capture ask shot serve."
                ),
                "fix": .string("Use Shot on a Mac for those for now."),
            ]),
            .object([
                "name": .string("macOnly"), "outcome": .string("pass"),
                "detail": .string("Text recognition (find_text and shot text), redaction by text (redact --detect), the text index, narration and system audio need a Mac, so they're left out on Linux by design. Of image files, Linux opens PNG and JPEG; HEIC, TIFF, BMP and WebP need a Mac."),
            ]),
            .object([
                "name": .string("emoji"), "outcome": .string("pass"),
                "detail": .string("A colour emoji font is installed, so emoji in text and notes draw in colour."),
            ]),
            .object([
                "name": .string("captureFolder"), "outcome": .string("pass"),
                "detail": .string("/home/me/Pictures/Shot can be read and holds 1 capture."),
            ]),
        ]),
    ]))
}

@Test func doctorOnLinuxNamesTheSession() {
    #expect(Doctor.platform(facts(session: "x11")).detail.hasSuffix("The session is X11."))
    let tty = Doctor.platform(facts(session: "tty"))
    #expect(tty.outcome == .warn)
    #expect(tty.detail.hasSuffix("XDG_SESSION_TYPE is tty, so this isn't an X11 or Wayland session, which capturing will need."))
    #expect(Doctor.platform(facts(session: nil)).detail.contains("XDG_SESSION_TYPE isn't set"))
}

@Test func doctorOnLinuxWarnsWithoutAColourEmojiFont() {
    let check = Doctor.emoji(facts(colorEmoji: false))
    #expect(check.outcome == .warn)
    #expect(check.fix == "Install one, such as Noto Color Emoji (fonts-noto-color-emoji on Debian and Ubuntu).")
    #expect(Doctor.json(Doctor.checks(facts(colorEmoji: false)))["ok"] == .bool(true))
}

@Test func doctorOnLinuxFailsOnlyOnAFolderItCantRead() {
    #expect(Doctor.linuxFolder(facts(folderExists: false)).outcome == .warn)
    let unreadable = Doctor.checks(facts(folderError: "Permission denied"))
    #expect(unreadable.last?.outcome == .fail)
    #expect(Doctor.json(unreadable)["ok"] == .bool(false))
}

@Test func toolsNotOnLinuxYetAreListedButAnswerThatTheyreNot() async {
    var tools = AgentTools(folder: URL(fileURLWithPath: "/shots"), entries: { [] }, preview: { _ in [] })
    tools.notOnLinuxYet = [AgentTools.annotate]
    #expect(tools.server(version: "1").tools.contains { $0.name == AgentTools.annotate })
    let result = await tools.call(AgentTools.annotate, .object([:]))
    #expect(result == MCPServer.ToolResult(content: [.text("annotate: not on Linux yet")], isError: true))
    #expect(ShotCommandError.notOnLinuxYet.exitCode == 69)
}

@Test func doctorOnLinuxSaysHowToLetAgentsCapture() {
    let off = Doctor.linuxAgents(facts(agentCapture: false))
    #expect(off.outcome == .warn)
    #expect(off.fix == "Run shot settings agent-capture on, if agents should take their own screenshots.")
    #expect(Doctor.linuxAgents(facts()).outcome == .pass)
}

@Test func doctorOnLinuxSaysWhetherShotServeAnswersAndWhatItCantCapture() {
    let running = Doctor.serve(facts(listening: true, status: serving()))
    #expect(running == Doctor.Check("serve", .pass, "shot serve 0.7.0 answers at /home/me/.local/share/dev.lorcan.Shot/agent.sock."))

    let limited = Doctor.serve(facts(listening: true, status: serving(limits: ["captureWindow": .string("Wayland asks before each window.")])))
    #expect(limited.outcome == .pass)
    #expect(limited.detail.hasSuffix("agent.sock. Wayland asks before each window."))

    let reason = JSONValue.string("The desktop portal isn't running.")
    let none = Doctor.serve(facts(listening: true, status: serving(capturer: "none", limits: ["captureArea": reason, "captureDisplay": reason, "listWindows": reason])))
    #expect(none.outcome == .warn)
    #expect(none.detail.hasSuffix("agent.sock. The desktop portal isn't running."))
    #expect(none.fix == "Fix what the screenshotPortal check says, then stop shot serve with pkill -f \"shot serve\"; the next capture starts it again.")
    let x11 = Doctor.serve(facts(session: "x11", listening: true, status: serving(capturer: "none", limits: ["listWindows": .string("DISPLAY isn't set.")])))
    #expect(x11.outcome == .warn)
    #expect(x11.fix == "Stop shot serve with pkill -f \"shot serve\", then run a capture from a terminal in your X11 desktop session to start it there.")

    let old = Doctor.serve(facts(listening: true, status: serving(version: "0.6.0")))
    #expect(old.outcome == .warn)
    #expect(old.detail.hasSuffix(" This command is 0.7.0."))
    #expect(old.fix == "Stop it with pkill -f \"shot serve\"; the next capture starts it again.")

    let stuck = Doctor.serve(facts(listening: true, status: .failure(.io("Shot closed the connection without a usable answer"))))
    #expect(stuck.outcome == .fail)
    #expect(Doctor.json(Doctor.checks(facts(listening: true, status: .failure(.io("gone")))))["ok"] == .bool(false))
}

@Test func doctorOnWaylandSaysWhetherTheDesktopPortalTakesScreenshots() {
    #expect(Doctor.portal(facts()) == nil)
    #expect(!Doctor.checks(facts()).contains { $0.name == "screenshotPortal" })

    let checks = Doctor.checks(facts(screenshotPortal: .success(1)))
    #expect(checks.map(\.name).prefix(2) == ["platform", "screenshotPortal"])
    #expect(checks[1] == Doctor.Check(
        "screenshotPortal", .pass,
        "The desktop portal can take screenshots (Screenshot version 1), so shot serve captures screens and areas through it, and windows the user picks in the desktop's screenshot dialog."
    ))

    let missing = Doctor.portal(facts(screenshotPortal: .failure(.unavailable("The desktop portal isn't running."))))
    #expect(missing?.outcome == .fail && missing?.detail == "The desktop portal isn't running.")
    #expect(missing?.fix == "Install xdg-desktop-portal and your desktop's backend (xdg-desktop-portal-gnome, xdg-desktop-portal-kde or xdg-desktop-portal-wlr), and run shot from a terminal in your Wayland desktop session.")
    #expect(Doctor.json(Doctor.checks(facts(screenshotPortal: .failure(.unavailable("gone")))))["ok"] == .bool(false))
}

@Test func doctorOnLinuxSaysWhereFFmpegIsAndWhatItEncodes() {
    let both = Doctor.FFmpegFacts(ffmpeg: "/usr/bin/ffmpeg", ffprobe: "/usr/bin/ffprobe", version: "6.1.1-3ubuntu5", encoders: ["libx264", "libx265", "aac"])
    let check = Doctor.ffmpeg(facts(ffmpeg: both))
    #expect(check?.outcome == .pass)
    #expect(check?.detail == "ffmpeg 6.1.1-3ubuntu5 at /usr/bin/ffmpeg, with ffprobe at /usr/bin/ffprobe, reads, trims and joins video. It encodes H.264 and HEVC.")
    // It comes after the serve check.
    #expect(Doctor.checks(facts(ffmpeg: both)).map(\.name).prefix(4) == ["platform", "letAgentsCaptureAndRecord", "serve", "ffmpeg"])
    #expect(Doctor.ffmpeg(facts()) == nil)

    var noHEVC = both
    noHEVC.encoders = ["libx264"]
    #expect(Doctor.ffmpeg(facts(ffmpeg: noHEVC))?.outcome == .pass)
    #expect(Doctor.ffmpeg(facts(ffmpeg: noHEVC))?.detail.hasSuffix("It encodes H.264, and has no libx265 for HEVC, which only exports that ask for it need.") == true)

    var noH264 = both
    noH264.encoders = ["libopenh264"]
    noH264.version = nil
    let weak = Doctor.ffmpeg(facts(ffmpeg: noH264))
    #expect(weak?.outcome == .warn)
    #expect(weak?.detail.hasPrefix("ffmpeg at /usr/bin/ffmpeg") == true)
    #expect(weak?.fix == "Install an ffmpeg built with libx264, such as your distribution's ffmpeg package.")
}

@Test func doctorOnLinuxWarnsWithoutFFmpeg() {
    let missing = Doctor.ffmpeg(facts(ffmpeg: Doctor.FFmpegFacts(ffmpeg: nil, ffprobe: nil)))
    #expect(missing?.outcome == .warn)
    #expect(missing?.detail == "Shot reads, trims and joins video with ffmpeg and ffprobe, and can't find ffmpeg or ffprobe.")
    #expect(missing?.fix == "Install ffmpeg (sudo apt install ffmpeg on Debian and Ubuntu), or set SHOT_FFMPEG and SHOT_FFPROBE to where they are.")
    let noProbe = Doctor.ffmpeg(facts(ffmpeg: Doctor.FFmpegFacts(ffmpeg: "/usr/bin/ffmpeg", ffprobe: nil)))
    #expect(noProbe?.detail.hasSuffix("can't find ffprobe.") == true)
    // Video isn't on Linux yet, so doctor still passes.
    #expect(Doctor.json(Doctor.checks(facts(ffmpeg: Doctor.FFmpegFacts(ffmpeg: nil, ffprobe: nil))))["ok"] == .bool(true))
}
