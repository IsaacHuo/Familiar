import Foundation
import SwiftData

/// Opt-in test dependency. There is no credential or network bypass in a device/Release build.
nonisolated enum FamiliarChatTestScenario {
    static var isEnabled: Bool {
#if DEBUG && targetEnvironment(simulator)
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("-familiar.ui-testing") && arguments.contains("-familiar.chat-testing")
#else
        return false
#endif
    }
    static var accessibilityEnabled: Bool {
        isEnabled && ProcessInfo.processInfo.arguments.contains("-familiar.accessibility-testing")
    }
    static var persistentStoreID: String? {
        guard isEnabled else { return nil }
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("-familiar.disk-testing"), let index = args.firstIndex(of: "-familiar.test-store-id"),
              args.indices.contains(index + 1) else { return nil }
        let value = args[index + 1]
        guard !value.isEmpty, value.count <= 64, value.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }) else { return nil }
        return value
    }
    @MainActor static func seedHistory(in controller: FamiliarChatController) {
        #if DEBUG && targetEnvironment(simulator)
        let args = ProcessInfo.processInfo.arguments
        guard isEnabled, controller.messages.isEmpty,
              let index = args.firstIndex(of: "-familiar.history-count"), args.indices.contains(index + 1),
              let count = Int(args[index + 1]), [100, 300].contains(count) else { return }
        controller.messages = (0..<count).map { index in
            .init(id: UUID(), role: .assistant,
                content: "# Reply \(index)\n\nA paragraph in the conversation.\n\n~~~swift\nlet value = \(index)\n~~~",
                createdAt: Date(timeIntervalSince1970: Double(index)), sequence: index,
                providerID: nil, modelID: nil, attachments: [])
        }
        #endif
    }
    @MainActor static func seedChatList(in context: ModelContext) throws {
        #if DEBUG && targetEnvironment(simulator)
        let args = ProcessInfo.processInfo.arguments
        guard isEnabled, let index = args.firstIndex(of: "-familiar.chat-list-count"), args.indices.contains(index + 1),
              let count = Int(args[index + 1]), [300, 1_000].contains(count),
              try context.fetchCount(FetchDescriptor<FamiliarConversation>()) == 0 else { return }
        let projects = (1...4).map { FamiliarProject(name: "Project \($0)") }
        for project in projects { context.insert(project) }
        for index in 0..<count {
            let time = Date().addingTimeInterval(-Double(index) * 60)
            let chat = FamiliarConversation(title: "Conversation \(index)", createdAt: time, updatedAt: time,
                project: index.isMultiple(of: 5) ? nil : projects[index % projects.count])
            context.insert(chat)
            context.insert(FamiliarMessage(role: .user, content: "Message preview \(index)", createdAt: time, sequence: 0, conversation: chat))
            context.insert(FamiliarConversationListStateRecord(conversationID: chat.id, preview: "Message preview \(index)", latestActivityAt: time))
        }
        try context.save()
        #endif
    }

    static var credential: String? { isEnabled ? "local-presentation-test" : nil }
}

#if DEBUG && targetEnvironment(simulator)
nonisolated struct FamiliarChatTestProvider: FamiliarModelProvider {
    let providerID = "presentation-test"

    func stream(request: FamiliarModelRequest) -> AsyncThrowingStream<FamiliarModelStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    // Runtime may append user-role catalog notices after a tool boundary.
                    // Fixtures must retain the original submitted task across those notices.
                    let prompt = request.messages.first { $0.role == .user }?.networkText ?? ""
                    if request.messages.first?.networkText?.contains("Generate up to three useful follow-up questions") == true {
                        let word = prompt.contains("Markdown") ? "Markdown report" : "Familiar reply"
                        let questions = ["How can I apply the " + word + " to a concrete example?", "What assumptions in this " + word + " should I verify?"]
                        let data = try JSONEncoder().encode(questions)
                        continuation.yield(.textDelta(String(decoding: data, as: UTF8.self)))
                        continuation.yield(.completed(.stop)); continuation.finish(); return
                    }
                    if request.messages.first?.networkText?.hasPrefix("Rewrite the supplied draft.") == true {
                        continuation.yield(.textDelta("Polished: " + prompt))
                        continuation.yield(.completed(.stop)); continuation.finish(); return
                    }
                    if prompt.localizedCaseInsensitiveContains("sources") {
                        let results = request.messages.filter { $0.role == .tool }
                        if results.count < 2 {
                            continuation.yield(.toolCallDelta(index: 0, id: "source-\(results.count)",
                                name: results.isEmpty ? "web_search" : "web_fetch",
                                arguments: results.isEmpty ? #"{"query":"verified source","maxResults":2}"#
                                    : #"{"url":"https://example.com/start"}"#))
                            continuation.yield(.completed(.toolCalls))
                        } else {
                            let startID = FamiliarSourceIdentifier.make(for: URL(string: "https://example.com/start")!)
                            let finalID = FamiliarSourceIdentifier.make(for: URL(string: "https://example.com/final")!)
                            let answer = prompt.localizedCaseInsensitiveContains("uncited")
                                ? "A reply without citations."
                                : "# Verified answer\n\nThe page contains a verified fact. [[\(startID)]]\n\nThe redirected URL is the same source. [[\(finalID)]]"
                            continuation.yield(.textDelta(answer))
                            continuation.yield(.completed(.stop))
                        }
                        continuation.finish(); return
                    }
                    let isLong = prompt.localizedCaseInsensitiveContains("long")
                    let results = request.messages.filter { $0.role == .tool }
                    if prompt.localizedCaseInsensitiveContains("question"), !results.contains(where: { $0.toolCallID == "presentation-question" }) {
                        continuation.yield(.toolCallDelta(index: 0, id: "presentation-question", name: "ask_user",
                            arguments: prompt.localizedCaseInsensitiveContains("options only")
                                ? #"{"question":"Which version should I use?","options":[{"id":"short","label":"Short version"},{"id":"full","label":"Full version"}],"allowCustom":false}"#
                                : #"{"question":"Which version should I use?","options":[{"id":"short","label":"Short version"},{"id":"full","label":"Full version"}],"allowCustom":true}"#))
                        continuation.yield(.completed(.toolCalls))
                        continuation.finish()
                        return
                    }
                    if prompt.localizedCaseInsensitiveContains("tools"), !results.contains(where: { $0.toolCallID?.hasPrefix("presentation-read-") == true }) {
                        if results.isEmpty { continuation.yield(.textDelta("# Tool workflow\n\nI will inspect the files.\n\n")) }
                        if !request.tools.contains(where: { $0.name == "file_read" }) {
                            continuation.yield(.toolCallDelta(index: 0, id: "presentation-load",
                                name: "tools_load", arguments: #"{"groups":["files"]}"#))
                        } else {
                            for index in 0..<3 {
                                continuation.yield(.toolCallDelta(index: index, id: "presentation-read-\(index)",
                                    name: "file_read", arguments: #"{"identifier":"file_fixture_\#(index)"}"#))
                            }
                        }
                        continuation.yield(.completed(.toolCalls))
                        continuation.finish()
                        return
                    }
                    if prompt.localizedCaseInsensitiveContains("file"), !results.contains(where: { $0.toolCallID == "presentation-file" }) {
                        let loaded = request.tools.contains { $0.name == "file_write" }
                        continuation.yield(.toolCallDelta(index: 0, id: loaded ? "presentation-file" : "presentation-load",
                            name: loaded ? "file_write" : "tools_load",
                            arguments: loaded
                                ? ##"{"title":"Presentation report","content":"# Report\n\nA saved result.","format":"markdown"}"##
                                : #"{"groups":["files"]}"#))
                        continuation.yield(.completed(.toolCalls))
                        continuation.finish()
                        return
                    }
                    let text = isLong
                        ? "# Stable heading\n\n" + String(repeating: "A continuous Familiar reply with readable paragraphs. 👋🏽\n\n", count: 100)
                        : "# Familiar\n\nA short continuous reply. 👨‍👩‍👧‍👦\n\nReply complete."
                    let body: String
                    if prompt.localizedCaseInsensitiveContains("markdown") {
                        body = "# Markdown report\n\n- First item\n- Second item\n\n> A stable quote\n\n~~~swift\nlet value = 123\n~~~\n\n| A | B |\n|---|---|\n| 1 | 2 |\n\n~~~mermaid\ngraph TD\nA --> B\n~~~\n\nReply complete."
                    } else { body = text }
                    var remainder = body
                    while !remainder.isEmpty {
                        try Task.checkCancellation()
                        let chunk = String(remainder.prefix(isLong ? 60 : 8))
                        continuation.yield(.textDelta(chunk))
                        remainder.removeFirst(chunk.count)
                        let interval = isLong ? (prompt.localizedCaseInsensitiveContains("tools") ? 350 : 110) : 40
                        try await Task.sleep(for: .milliseconds(interval))
                        if prompt.localizedCaseInsensitiveContains("error"), remainder.count < text.count / 2 {
                            throw NSError(domain: "PresentationTest", code: 1,
                                userInfo: [NSLocalizedDescriptionKey: "Presentation test interrupted"])
                        }
                    }
                    continuation.yield(.completed(.stop))
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

nonisolated struct FamiliarChatTestReadTool: FamiliarTool {
    struct Input: Decodable, Sendable { let identifier: String }
    private struct Output: Encodable, Sendable {
        let fileIdentifier: String
        let filename: String
        let extractedBy = "presentation-fixture"
        let characterCount = 23
        let truncated = false
        let text = "Local test file content"
    }
    let manifest = FamiliarFileReadTool().manifest
    func execute(_ input: Input, context: FamiliarToolContext) async throws -> FamiliarToolOutcome {
        try await Task.sleep(for: .milliseconds(500))
        return .result(.init(envelope: try FamiliarToolResultEnvelope(
            model: Output(fileIdentifier: input.identifier, filename: input.identifier + ".txt"),
            presentation: .document(.init(summary: "Read presentation fixture", title: input.identifier + ".txt",
                text: "Local test file content", mimeType: "text/plain"))
        )))
    }
}

/// Deterministic Web adapters behind the Simulator-only presentation scenario.
nonisolated struct FamiliarChatTestSearchProvider: FamiliarSearchProvider {
    let id = "duckduckgo"
    func search(request: FamiliarSearchRequest, apiKey: String?) async throws -> FamiliarSearchResponse {
        let urls = ["https://example.com/start", "https://example.com/unused"]
        return .init(providerID: id, results: urls.prefix(request.maximumResults).enumerated().map { index, value in
            .init(sourceID: FamiliarSourceIdentifier.make(for: URL(string: value)!), position: index + 1,
                title: index == 0 ? "Verified source" : "Unused search result", url: value, displayURL: "example.com", snippet: nil)
        }, truncated: false)
    }
}

nonisolated struct FamiliarChatTestWebTransport: FamiliarWebHTTPTransport {
    func get(_ url: URL, bodyLimit: Int, redirectLimit: Int, timeout: Duration) async throws -> FamiliarRestrictedHTTPResponse {
        .init(finalURL: URL(string: "https://example.com/final")!, statusCode: 200,
            headers: ["content-type": "text/html; charset=utf-8"],
            body: Data("<html><title>Verified source</title><article>A verified fact in the captured page. This deterministic article contains enough original body text for the production extractor to accept and cite it.</article></html>".utf8))
    }
}
#endif
