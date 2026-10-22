import CoreGraphics
import Foundation
import Testing
@testable import ShotCore

/// `text`'s words said one after another from `start`, each `each` seconds long with no gap.
private func said(_ text: String, from start: Double, each: Double = 0.3) -> [Narration.Word] {
    text.split(separator: " ").enumerated().map { index, word in
        Narration.Word(text: (index == 0 ? "" : " ") + word, start: start + Double(index) * each, end: start + Double(index + 1) * each)
    }
}

@Test func aSentenceEndsACaption() {
    let captions = Captions.captions(said("Click Save. Then close the window.", from: 1), duration: 10)
    #expect(captions.map(\.text) == ["Click Save.", "Then close the window."])
    #expect(captions[0].start == 1)
}

@Test func aPauseEndsACaption() {
    let captions = Captions.captions(said("open settings", from: 0) + said("now pick general", from: 3), duration: 10)
    #expect(captions.map(\.text) == ["open settings", "now pick general"])
}

@Test func aLongRunIsSplitIntoCaptionsOfTwoBalancedLines() {
    let text = "this is a long stretch of narration without any full stops that keeps going on and on about the settings window and what each switch does in it"
    let captions = Captions.captions(said(text, from: 0, each: 0.2), duration: 60)
    #expect(captions.count > 1)
    for caption in captions {
        let lines = caption.text.components(separatedBy: "\n")
        #expect(lines.count <= 2)
        #expect(lines.allSatisfy { $0.count <= 42 })
        #expect(caption.end - caption.start <= 7)
    }
    #expect(captions.map { $0.text.replacingOccurrences(of: "\n", with: " ") }.joined(separator: " ") == text)
}

@Test func twoLinesAreBalanced() {
    let split = Captions.lines("Choose General, then turn on Open at login so it starts")
    #expect(split == "Choose General, then turn on\nOpen at login so it starts")
    #expect(Captions.lines("Short one") == "Short one")
    #expect(Captions.lines(String(repeating: "word ", count: 30)) == nil)
}

@Test func aShortCaptionStaysUpLongEnoughToRead() {
    let captions = Captions.captions([Narration.Word(text: "OK.", start: 2, end: 2.2)] + said("Next we export it as a GIF.", from: 6), duration: 10)
    #expect(abs(captions[0].end - 2.8) < 0.001)
    // A long one gets at least a second per 20 characters, but never runs into the next.
    let crowded = Captions.captions(said("This one has quite a lot to read in it.", from: 0, each: 0.1) + said("Next.", from: 1.2), duration: 10)
    #expect(crowded[0].end <= crowded[1].start - Captions.gap + 1e-9)
}

@Test func captionsFollowTheTrimsAndCuts() throws {
    let source = URL(fileURLWithPath: "/tmp/recording.mov")
    var project = Project(source: source, duration: 10, canvasSize: CGSize(width: 1920, height: 1080), hasAudio: true)
    // Keep 2–4 s and 6–10 s of the recording: 0–2 trimmed, 4–6 cut.
    project = try #require(project.trimmingMain(.start, toSource: 2))
    project = try #require(project.deleting(range: 2 ..< 4))
    let placed = Captions.placements([
        Captions.Caption(text: "trimmed off", start: 0.5, end: 1.5),
        Captions.Caption(text: "kept", start: 2.5, end: 3.5),
        Captions.Caption(text: "after the cut", start: 7, end: 8),
    ], in: project, source: source)
    #expect(placed.map(\.caption.text) == ["kept", "after the cut"])
    #expect(abs(placed[0].start - 0.5) < 0.001 && abs(placed[0].duration - 1) < 0.001)
    #expect(abs(placed[1].start - 3) < 0.001)
    // A caption across the cut shows on both sides of it.
    let across = Captions.placements([Captions.Caption(text: "across", start: 3.5, end: 7)], in: project, source: source)
    #expect(across.count == 2)
    #expect(abs(across[0].start - 1.5) < 0.001 && abs(across[0].duration - 0.5) < 0.001)
    #expect(abs(across[1].start - 2) < 0.001 && abs(across[1].duration - 1) < 0.001)
}

@Test func aCaptionIsWhiteTextInAnOpaqueBoxNearTheBottom() throws {
    let canvas = CGSize(width: 1920, height: 1080)
    let annotation = Captions.annotation(Captions.Caption(text: "Click Save", start: 0, end: 1), canvas: canvas)
    #expect(annotation.color == RGBA(1, 1, 1) && annotation.fill?.a == 1)
    #expect(annotation.alignment == .center)
    let box = try #require(annotation.textBox)
    #expect(abs(box.midX - canvas.width / 2) <= 1)
    #expect(box.maxY <= canvas.height * 0.93 && box.maxY > canvas.height * 0.85)
    if case let .text(_, _, size) = annotation.kind {
        #expect(size == 54)
    }
    // A small frame still gets text big enough to read in a GIF.
    let small = Captions.annotation(Captions.Caption(text: "Hi", start: 0, end: 1), canvas: CGSize(width: 1440, height: 200))
    if case let .text(_, _, size) = small.kind {
        #expect(size == 28)
    }
}
