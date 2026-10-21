import Foundation
import Testing
@testable import ShotCore

private let server = MCPServer(
    name: "shot",
    version: "1.0",
    tools: [MCPServer.Tool(name: "latest_capture", description: "The newest capture", inputSchema: .object(["type": .string("object")]))],
    call: { name, arguments, _ in
        MCPServer.ToolResult(content: [.text("\(name) kind=\(arguments["kind"]?.string ?? "none")")])
    }
)

@Test func initializeNamesTheServerAndOffersTools() async {
    let reply = await server.respond(to: #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"test","version":"1"}}}"#)
    #expect(reply == #"{"id":1,"jsonrpc":"2.0","result":{"capabilities":{"tools":{}},"protocolVersion":"2025-03-26","serverInfo":{"name":"shot","version":"1.0"}}}"#)
}

@Test func initializeWithAnUnknownVersionOffersTheNewest() async {
    let reply = await server.respond(to: #"{"jsonrpc":"2.0","id":"a","method":"initialize","params":{"protocolVersion":"1999-01-01"}}"#)
    #expect(reply?.contains(#""protocolVersion":"\#(MCPServer.protocolVersion)""#) == true)
    #expect(reply?.hasPrefix(#"{"id":"a","#) == true)
}

@Test func notificationsAndBlankLinesGetNoReply() async {
    #expect(await server.respond(to: #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#) == nil)
    #expect(await server.respond(to: "") == nil)
    #expect(await server.respond(to: "  \n") == nil)
}

@Test func pingRepliesEmpty() async {
    #expect(await server.respond(to: #"{"jsonrpc":"2.0","id":7,"method":"ping"}"#) == #"{"id":7,"jsonrpc":"2.0","result":{}}"#)
}

@Test func toolsListDescribesEachTool() async {
    let reply = await server.respond(to: #"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#)
    #expect(reply == #"{"id":2,"jsonrpc":"2.0","result":{"tools":[{"description":"The newest capture","inputSchema":{"type":"object"},"name":"latest_capture"}]}}"#)
}

@Test func toolsListMarksAReadOnlyToolWithItsHint() async {
    let tool = MCPServer.Tool(name: "list_captures", description: "Recent captures", inputSchema: .object(["type": .string("object")]), readOnly: true)
    let listing = MCPServer(name: "shot", version: "1.0", tools: [tool]) { _, _, _ in MCPServer.ToolResult(content: []) }
    let reply = await listing.respond(to: #"{"jsonrpc":"2.0","id":3,"method":"tools/list"}"#)
    #expect(reply == #"{"id":3,"jsonrpc":"2.0","result":{"tools":[{"annotations":{"readOnlyHint":true},"description":"Recent captures","inputSchema":{"type":"object"},"name":"list_captures"}]}}"#)
}

@Test func toolsCallRunsTheToolWithItsArguments() async {
    let reply = await server.respond(to: #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"latest_capture","arguments":{"kind":"video"}}}"#)
    #expect(reply == #"{"id":3,"jsonrpc":"2.0","result":{"content":[{"text":"latest_capture kind=video","type":"text"}],"isError":false}}"#)
}

@Test(arguments: ["Latest-Capture", " latest capture ", "LATEST_CAPTURE"])
func toolNamesMatchLoosely(_ name: String) async {
    let reply = await server.respond(to: #"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"\#(name)"}}"#)
    #expect(reply?.contains("latest_capture kind=none") == true)
}

@Test func argumentsThatArentAnObjectAreIgnored() async {
    let reply = await server.respond(to: #"{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"latest_capture","arguments":"video"}}"#)
    #expect(reply?.contains("latest_capture kind=none") == true)
}

@Test func anUnknownToolIsAnInvalidParamsError() async {
    let reply = await server.respond(to: #"{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"delete_everything"}}"#)
    #expect(reply == #"{"error":{"code":-32602,"message":"Unknown tool: delete_everything"},"id":6,"jsonrpc":"2.0"}"#)
}

@Test func anUnknownMethodIsMethodNotFound() async {
    let reply = await server.respond(to: #"{"jsonrpc":"2.0","id":8,"method":"resources/list"}"#)
    #expect(reply == #"{"error":{"code":-32601,"message":"Method not found: resources/list"},"id":8,"jsonrpc":"2.0"}"#)
}

@Test func malformedJSONIsAParseError() async {
    #expect(await server.respond(to: "{not json") == #"{"error":{"code":-32700,"message":"Parse error"},"id":null,"jsonrpc":"2.0"}"#)
}

@Test(arguments: [#"[1,2]"#, #"{"id":9,"method":"ping"}"#, #"{"jsonrpc":"2.0","id":9}"#])
func aMessageThatIsntARequestIsInvalid(_ line: String) async {
    #expect(await server.respond(to: line)?.contains(#""code":-32600"#) == true)
}

@Test func repliesAreOneLineEvenWithNewlinesInText() async {
    let multiline = MCPServer(name: "shot", version: "1", tools: server.tools) { _, _, _ in
        MCPServer.ToolResult(content: [.text("line one\nline two"), .image(data: "AAAA", mimeType: "image/jpeg")])
    }
    let reply = await multiline.respond(to: #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"latest_capture"}}"#)
    #expect(reply?.contains("\n") == false)
    #expect(reply?.contains(#"{"data":"AAAA","mimeType":"image/jpeg","type":"image"}"#) == true)
}

@Test func jsonNumbersReadFromQuotedStringsToo() throws {
    let value = try JSONDecoder().decode(JSONValue.self, from: Data(#"{"a":10,"b":"25","c":true}"#.utf8))
    #expect(value["a"]?.number == 10)
    #expect(value["b"]?.number == 25)
    #expect(value["c"]?.number == nil)
    #expect(value["c"] == .bool(true))
}

@Test func initializeKeepsTheClientsNameForProvenance() async {
    let fresh = MCPServer(name: "shot", version: "1.0", tools: []) { _, _, _ in MCPServer.ToolResult(content: []) }
    #expect(fresh.client == nil)
    _ = await fresh.respond(to: #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","clientInfo":{"name":"claude-code","version":"2.1.0"}}}"#)
    #expect(fresh.client == MCPServer.Client(name: "claude-code", version: "2.1.0"))
}

@Test func aClientWithNoNameIsntKept() async {
    let fresh = MCPServer(name: "shot", version: "1.0", tools: []) { _, _, _ in MCPServer.ToolResult(content: []) }
    _ = await fresh.respond(to: #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"clientInfo":{"name":"","version":"1"}}}"#)
    #expect(fresh.client == nil)
    _ = await fresh.respond(to: #"{"jsonrpc":"2.0","id":2,"method":"initialize","params":{"clientInfo":{"name":"cursor"}}}"#)
    #expect(fresh.client == MCPServer.Client(name: "cursor", version: nil))
}
