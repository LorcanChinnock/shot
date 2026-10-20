import Foundation
import Testing
@testable import ShotModel

private func facts(session: String? = "wayland", folderExists: Bool = true, folderError: String? = nil) -> Doctor.LinuxFacts {
    Doctor.LinuxFacts(
        version: "0.7.0", settingsFile: "/home/me/.config/dev.lorcan.Shot.plist", sessionType: session, folder: "/home/me/Pictures/Shot",
        folderExists: folderExists, folderError: folderError, captures: 1
    )
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
                "name": .string("notOnLinuxYet"), "outcome": .string("warn"),
                "detail": .string("Only shot version, help, doctor and mcp's tool list work on Linux so far. Every other command and MCP tool answers that it's not on Linux yet."),
                "fix": .string("Use Shot on a Mac for those for now."),
            ]),
            .object([
                "name": .string("macOnly"), "outcome": .string("pass"),
                "detail": .string("Text recognition (find_text and shot text), redaction by text (redact --detect), the text index, narration and system audio need a Mac, so they're left out on Linux by design. Of image files, Linux opens PNG and JPEG; HEIC, TIFF, BMP and WebP need a Mac."),
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
