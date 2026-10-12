import Foundation
import Testing
@testable import ShotModel

private func decodeRequest(_ json: String) -> ShotCommandError? {
    do {
        _ = try AgentRequest.decode(Data(json.utf8))
        return nil
    } catch {
        return error
    }
}

@Test func aRequestRoundTripsAsOneLine() throws {
    let request = AgentRequest(.capture, window: "Simulator")
    let line = request.line
    #expect(line.last == UInt8(ascii: "\n"))
    #expect(line.dropLast().contains(UInt8(ascii: "\n")) == false)
    #expect(try AgentRequest.decode(line) == request)
    #expect(try AgentRequest.decode(AgentRequest(.status).line) == AgentRequest(.status))
    let record = AgentRequest(.record, window: "Simulator", duration: 2.5)
    #expect(try AgentRequest.decode(record.line) == record)
    #expect(try AgentRequest.decode(AgentRequest(.stop, id: "ab12cd34").line) == AgentRequest(.stop, id: "ab12cd34"))
    #expect(try AgentRequest.decode(AgentRequest(.stop).line) == AgentRequest(.stop))
    #expect(try AgentRequest.decode(AgentRequest(.windows).line) == AgentRequest(.windows))
    let target = AgentTarget(window: "Apple", bundleID: "com.apple.Safari", rect: [0, 0, 800, 120], noShadow: true, waitStable: 5)
    #expect(try AgentRequest.decode(AgentRequest(.capture, target: target).line).target == target)
    let display = AgentRequest(.record, target: AgentTarget(display: 2), duration: 10)
    #expect(try AgentRequest.decode(display.line) == display)
}

@Test func aPlainRequestSendsNoTargetFieldsItDoesntUse() {
    let line = String(decoding: AgentRequest(.capture, window: "Simulator").line, as: UTF8.self)
    for key in ["bundleID", "display", "rect", "noShadow", "waitStable"] {
        #expect(!line.contains(key), "\(key)")
    }
    #expect(AgentRequest(.capture, target: AgentTarget(window: "Simulator")) == AgentRequest(.capture, window: "Simulator"))
}

@Test(arguments: [
    ("[]", "the request isn't a JSON object"),
    ("nope", "the request isn't a JSON object"),
    (#"{"op":"capture","window":"a"}"#, "this Shot speaks only version 1 of the agent protocol"),
    (#"{"v":2,"op":"capture","window":"a"}"#, "this Shot speaks only version 1 of the agent protocol"),
    (#"{"v":1,"op":"delete"}"#, #"unknown op "delete""#),
    (#"{"v":1}"#, "unknown op (none)"),
    (#"{"v":1,"op":"capture"}"#, "capture needs a window"),
    (#"{"v":1,"op":"capture","window":" "}"#, "capture needs a window"),
    (#"{"v":1,"op":"record"}"#, "record needs a window"),
    (#"{"v":1,"op":"capture","bundleID":" "}"#, "capture needs a window"),
    (#"{"v":1,"op":"capture","display":0}"#, "capture needs a display numbered from 1"),
    (#"{"v":1,"op":"capture","display":1.5}"#, "capture needs a display numbered from 1"),
    (#"{"v":1,"op":"capture","display":1,"window":"a"}"#, "capture takes a window or a display, not both"),
    (#"{"v":1,"op":"capture","window":"a","rect":[0,0,10]}"#, "capture needs a rect of x, y, width and height"),
    (#"{"v":1,"op":"capture","window":"a","rect":"0,0,10,10"}"#, "capture needs a rect of x, y, width and height"),
    (#"{"v":1,"op":"capture","window":"a","waitStable":60}"#, "capture can wait for the window to settle for above 0 and at most 30 seconds"),
    (#"{"v":1,"op":"record","window":"a","waitStable":5}"#, "record can't wait for the window to settle"),
    (#"{"v":1,"op":"record","window":"a","duration":0}"#, "duration must be above 0 and at most 600 seconds"),
    (#"{"v":1,"op":"record","window":"a","duration":601}"#, "duration must be above 0 and at most 600 seconds"),
])
func aBadRequestIsAUsageError(_ json: String, _ message: String) throws {
    let error = try #require(decodeRequest(json))
    #expect(error.exitCode == 64)
    #expect(error.message.hasPrefix(message), "\(error.message)")
}

@Test func anAnswerRoundTripsWithItsFieldsOrItsError() throws {
    let fields: [String: JSONValue] = ["path": .string("/a/b.png"), "bytes": .number(10)]
    let success = AgentResponse.success(fields)
    #expect(String(decoding: success.line, as: UTF8.self) == #"{"bytes":10,"ok":true,"path":"/a/b.png"}"# + "\n")
    #expect(try AgentResponse.decode(success.line) == success)
    #expect(try AgentResponse.decode(success.line).get() == fields)
    for error in [ShotCommandError.busy("recording"), .noPermission("no"), .unavailable("off"), .noInput("No open window matches")] {
        let failure = AgentResponse.failure(error)
        #expect(try AgentResponse.decode(failure.line) == failure)
        #expect(throws: error) { try AgentResponse.decode(failure.line).get() }
    }
}

@Test func anAnswerItCantReadIsAnIOError() throws {
    for json in ["", "[]", #"{"path":"/a"}"#, #"{"ok":"yes"}"#] {
        #expect(throws: ShotCommandError.io("Shot's answer wasn't one it can read; update Shot or the command line so they match")) {
            try AgentResponse.decode(Data(json.utf8))
        }
    }
    #expect(try AgentResponse.decode(Data(#"{"ok":false}"#.utf8)) == .failure(.internal("Shot gave no reason")))
}
