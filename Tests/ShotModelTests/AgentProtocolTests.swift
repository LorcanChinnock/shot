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
