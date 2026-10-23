import Foundation
import Testing
@testable import ShotCore

private func recording(frames: Int, text: (Int) -> [String] = { _ in [] }) -> BugReport.Input {
    BugReport.Input(app: "Safari", windowTitle: "Checkout", duration: 30, frames: (0 ..< frames).map {
        BugReport.Frame(time: Double($0) * 3, text: text($0), said: [Narration.Phrase(text: "step \($0)", start: Double($0) * 3, end: Double($0) * 3 + 1)])
    })
}

@Test func framesAreSpreadEvenlyAndKeepTheFirstAndLast() {
    #expect(BugReport.evenlySpread(10, keeping: 3) == [0, 5, 9])
    #expect(BugReport.evenlySpread(2, keeping: 3) == [0, 1])
    #expect(BugReport.evenlySpread(5, keeping: 1) == [0])
    #expect(BugReport.evenlySpread(0, keeping: 3).isEmpty)
}

@Test func theOnDeviceBudgetKeepsFewFramesAndSaysSoWhenItTrims() {
    let prepared = BugReport.prepare(recording(frames: 12), budget: .onDevice)
    #expect(prepared.frames.count == 3 && prepared.frames.first == 0 && prepared.frames.last == 11)
    #expect(prepared.trimmed)
    #expect(!BugReport.prepare(recording(frames: 2), budget: .onDevice).trimmed)
}

@Test func theTextOverTheBudgetIsLeftOutOfThePromptButStillCheckedAgainst() {
    let long = (0 ..< 50).map { "Line number \($0) of the page text" }
    let prepared = BugReport.prepare(recording(frames: 1) { _ in long }, budget: .onDevice)
    #expect(prepared.request.prompt.count < 3000)
    #expect(prepared.trimmed)
    #expect(prepared.text.count == 50)
}

@Test func aLineRepeatedOnTheNextFrameIsSaidOnce() {
    let prepared = BugReport.prepare(recording(frames: 2) { _ in ["Menu", "Total $5"] }, budget: .provider)
    #expect(prepared.request.prompt.components(separatedBy: "Total $5").count == 2)
}

@Test func thePromptNamesTheSourceTheNotesAndWhatWasSaid() {
    var input = recording(frames: 2)
    input.notes = ["the total is wrong"]
    let prompt = BugReport.prepare(input, budget: .provider).request.prompt
    #expect(prompt.contains("screen recording that runs 30.0s"))
    #expect(prompt.contains("Safari, window \"Checkout\""))
    #expect(prompt.contains("\"the total is wrong\""))
    #expect(prompt.contains("Said at 0.0–1.0s: \"step 0\""))
    let shot = BugReport.prepare(BugReport.Input(frames: [BugReport.Frame()]), budget: .provider).request.prompt
    #expect(shot.contains("The image is a screenshot.") && !shot.contains("What the user said"))
}

@Test func theReplySchemaIsOneEveryProviderAccepts() {
    #expect(ProviderSchema.problem(with: BugReport.schema) == nil)
}

@Test func errorTextIsQuotedFromTheTextTheMacReadNotFromTheModel() {
    let reply: JSONValue = .object([
        "title": .string("Checkout fails"),
        "steps": .array([.string("1. Open the cart"), .string("Press Pay")]),
        "expected": .string("An order is placed"),
        "actual": .string("An error appears"),
        "errors": .array([.string("payment declined: code 402"), .string("made up message")]),
    ])
    let markdown = BugReport.markdown(from: reply, readText: ["Payment declined: Code 402 (card)", "Pay"])
    #expect(markdown.hasPrefix("## Checkout fails\n"))
    #expect(markdown.contains("1. Open the cart\n2. Press Pay"))
    #expect(markdown.contains("> Payment declined: Code 402 (card)"))
    #expect(!markdown.contains("made up"))
}

@Test func aReplyWithNothingInItStillMakesAReport() {
    let markdown = BugReport.markdown(from: .object([:]), readText: [])
    #expect(markdown == "## Bug report\n")
}

@Test func anActualThatRepeatsTheExpectedIsLeftOut() {
    let reply: JSONValue = .object(["title": .string("Upload"), "expected": .string("A program is created."), "actual": .string("a program is created.")])
    let markdown = BugReport.markdown(from: reply, readText: [])
    #expect(markdown.contains("### Expected"))
    #expect(!markdown.contains("### Actual"))
}

@Test func aRefusalForContextLengthIsRecognised() {
    #expect(ChatProvider.Failure.server(status: 400, message: "request (9049 tokens) exceeds the available context size (4096 tokens)").isContextTooSmall)
    #expect(ChatProvider.Failure.server(status: 413, message: "prompt is too long").isContextTooSmall)
    #expect(!ChatProvider.Failure.server(status: 401, message: "invalid context key").isContextTooSmall)
    #expect(!ChatProvider.Failure.server(status: 400, message: "model not found").isContextTooSmall)
    #expect(!ChatProvider.Failure.tooLarge.isContextTooSmall)
}
