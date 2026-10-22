import Foundation
import Testing
@testable import ShotCore

private let path = "/Users/me/Pictures/Shot/Shot 2026-10-22 at 09.14.03.png"

private func record(_ marks: [CaptureMark], source: CaptureRecord.Source? = CaptureRecord.Source(mode: "window", app: "Safari", windowTitle: "Settings")) -> CaptureRecord {
    CaptureRecord(kind: "image", created: Date(timeIntervalSince1970: 0), size: .init(width: 1600, height: 1000), scale: 2, source: source, annotations: marks)
}

private func line(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat = 100, height: CGFloat = 20) -> CaptureText.Line {
    CaptureText.Line(text: text, box: CGRect(x: x, y: y, width: width, height: height))
}

private let screen = CaptureText(width: 1600, height: 1000, lines: [
    line("Save changes", x: 600, y: 380, width: 140),
    line("Billing", x: 40, y: 40),
    line("Plan: Pro", x: 40, y: 70),
    line("jane@example.com", x: 900, y: 60, width: 200),
])

@Test func withTheRecordOffThePromptIsThePathAndTheOpenLine() {
    let prompt = AgentPrompt(path: path, text: screen, findText: true)
    #expect(prompt.string == "Screenshot from Shot: \(path)\nOpen the image first; the user's marks are drawn on it.")
}

@Test func theUsersNotesComeFirstAsTheTask() {
    let prompt = AgentPrompt(path: path, record: record([
        CaptureMark(type: "arrow", from: [410, 220], to: [612, 388], color: "red"),
        CaptureMark(type: "note", rect: [700, 300, 180, 32], text: "this should be 8pt from the edge", color: "yellow"),
    ]), text: screen)
    #expect(prompt.lines == [
        "this should be 8pt from the edge",
        "Screenshot from Shot: \(path)",
        "Open the image first; the user's marks are drawn on it.",
        "Captured from Safari, window \"Settings\". 1600×1000 px, 1 pt = 2 px.",
        "What the user marked (pixels, top-left origin):",
        "- arrow from (410, 220) to (612, 388), red, pointing at \"Save changes\"",
    ])
}

@Test func withoutNotesThePromptOpensWithAPlainLine() {
    let prompt = AgentPrompt(path: path, record: record([CaptureMark(type: "rectangle", rect: [30, 30, 200, 70], color: "yellow")], source: nil), text: screen)
    #expect(prompt.lines == [
        "Here's a screenshot I marked up:",
        "Screenshot from Shot: \(path)",
        "Open the image first; the user's marks are drawn on it.",
        "1600×1000 px, 1 pt = 2 px.",
        "What the user marked (pixels, top-left origin):",
        "- rectangle at (30, 30), 200×70, yellow, around \"Billing Plan: Pro\"",
    ])
}

@Test func eachMarkKindReadsAsAPlainLine() {
    let prompt = AgentPrompt(path: path, record: record([
        CaptureMark(type: "line", from: [0, 0], to: [10, 10], color: "blue"),
        CaptureMark(type: "rounded", rect: [1, 2, 3, 4], color: "red"),
        CaptureMark(type: "ellipse", rect: [590, 370, 160, 40], color: "green"),
        CaptureMark(type: "highlight", rect: [595, 378, 150, 24], color: "yellow"),
        CaptureMark(type: "spotlight", rect: [10, 10, 50, 50], note: "the area outside is dimmed"),
        CaptureMark(type: "text", rect: [800, 500, 120, 30], text: "too \"tight\"", color: "red"),
        CaptureMark(type: "counter", center: [620, 392], number: 2, color: "red"),
        CaptureMark(type: "pen", rect: [5, 6, 7, 8], points: [[5, 6], [12, 14]], color: "black"),
        CaptureMark(type: "marker", rect: [38, 68, 104, 24], points: [[38, 80], [142, 80]], color: "yellow"),
        CaptureMark(type: "image", rect: [100, 100, 50, 50]),
    ], source: nil), text: screen)
    #expect(Array(prompt.lines.dropFirst(5)) == [
        "- line from (0, 0) to (10, 10), blue",
        "- rectangle at (1, 2), 3×4, red",
        "- ellipse at (590, 370), 160×40, green, around \"Save changes\"",
        "- highlight at (595, 378), 150×24, yellow, over \"Save changes\"",
        "- spotlight at (10, 10), 50×50 (the area outside is dimmed)",
        "- text \"too 'tight'\" at (800, 500), red",
        "- number 2 at (620, 392), red, on \"Save changes\"",
        "- pen stroke at (5, 6), 7×8, black",
        "- marker stroke at (38, 68), 104×24, yellow, over \"Plan: Pro\"",
        "- placed image at (100, 100), 50×50",
    ])
}

@Test func anArrowTipJustShortOfTextStillPointsAtIt() {
    let lines = [line("Save changes", x: 600, y: 380, width: 140)]
    #expect(AgentPrompt.text(at: CGPoint(x: 590, y: 390), in: lines) == "Save changes")
    #expect(AgentPrompt.text(at: CGPoint(x: 560, y: 390), in: lines) == nil)
}

@Test func blurredAreasAreCountedAndTheirTextIsNeverQuoted() {
    let prompt = AgentPrompt(path: path, record: record([
        CaptureMark(type: "blur", rect: [890, 50, 220, 40], note: "redacted, content hidden"),
        CaptureMark(type: "pixelate", rect: [0, 0, 10, 10], note: "redacted, content hidden"),
        CaptureMark(type: "arrow", from: [800, 200], to: [950, 70], color: "red"),
    ]), text: screen, findText: true)
    #expect(Array(prompt.lines.dropFirst(4)) == [
        "What the user marked (pixels, top-left origin):",
        "- arrow from (800, 200) to (950, 70), red",
        "2 areas are blurred on purpose; don't try to read what's under them.",
        "For the text in the capture, call Shot's find_text with this path.",
    ])
    #expect(!prompt.string.contains("jane"))
    let one = AgentPrompt(path: path, record: record([CaptureMark(type: "blur", rect: [0, 0, 10, 10])]))
    #expect(one.lines.last == "1 area is blurred on purpose; don't try to read what's under it.")
}

@Test func onlyTenMarksAreListed() {
    let marks = (0 ..< 14).map { CaptureMark(type: "counter", center: [Double($0) * 10, 500], number: $0 + 1, color: "red") }
    let prompt = AgentPrompt(path: path, record: record(marks), text: screen)
    #expect(prompt.lines.filter { $0.hasPrefix("- number") }.count == 10)
    #expect(prompt.lines.last == "- and 4 more")
}

@Test func longTextIsCutShortOnOneLine() {
    let quoted = AgentPrompt.quote(String(repeating: "word ", count: 30) + "\nend")
    #expect(quoted.count == AgentPrompt.maxQuote)
    #expect(quoted.hasSuffix("…"))
    #expect(!quoted.contains("\n"))
}

@Test func aBusyCaptureStaysShort() {
    let marks = (0 ..< 12).map { CaptureMark(type: "rectangle", rect: [Double($0) * 120, 30, 110, 70], color: "yellow") }
    let busy = CaptureText(width: 1600, height: 1000, lines: (0 ..< 12).map { line(String(repeating: "Label \($0) ", count: 12), x: CGFloat($0) * 120, y: 40) })
    let prompt = AgentPrompt(path: path, record: record(marks + [CaptureMark(type: "note", rect: [0, 0, 1, 1], text: "fix the spacing")]), text: busy)
    // The notes come on top of the budget, and the marks that don't fit are counted.
    #expect(prompt.lines.dropFirst().dropLast().joined(separator: "\n").count <= AgentPrompt.maxLength)
    #expect(prompt.lines.filter { $0.hasPrefix("- rectangle") }.count < 10)
    #expect(prompt.lines.last?.hasPrefix("- and ") == true)
}
