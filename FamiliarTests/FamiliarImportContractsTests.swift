import Foundation
import SwiftData
import Testing
@testable import Familiar

@Suite("Familiar imported workspace contracts")
struct FamiliarImportContractsTests {
    @Test @MainActor func defaultProjectAdoptionPreservesHistory() throws {
        let container = try FamiliarTestStore.make()
        let context = container.mainContext
        let chat = FamiliarConversation(title: "Existing conversation")
        let message = FamiliarMessage(role: .user, content: "Keep this", sequence: 0, conversation: chat)
        let run = FamiliarAgentRun(runtimeID: UUID().uuidString, conversation: chat)
        context.insert(chat); context.insert(message); context.insert(run)
        try context.save()
        let service = FamiliarProjectService()
        let first = try service.ensureDefaultProject(in: context)
        let second = try service.ensureDefaultProject(in: context)
        #expect(first.id == FamiliarProject.dailyProjectID)
        #expect(first.id == second.id)
        #expect(chat.project?.id == first.id)
        #expect(chat.messages.first?.content == "Keep this")
        #expect(run.project == nil)
        #expect(try context.fetch(FetchDescriptor<FamiliarProject>()).count == 1)
        #expect(throws: FamiliarProjectServiceError.protectedProject) { try service.setArchived(true, for: first, in: context) }
        #expect(throws: FamiliarProjectServiceError.protectedProject) { try service.permanentlyDelete(first, in: context) }
        try service.update(first, name: "Not the default name", summary: "Updated context", in: context)
        #expect(first.name == "Daily Chat")
        #expect(first.summary == "Updated context")
    }

    @Test func foreignModelIDsAreNotRewrittenToDeepSeek() {
        #expect(FamiliarProviderCatalog.normalizedModelID("custom-model", providerID: "custom-instance") == "custom-model")
    }

    @Test func instanceIdentityIsIndependentOfProtocol() {
        let template = FamiliarProviderCatalog.templates.first { $0.id == "anthropic" }!
        let work = template.instance(id: "work")
        let personal = template.instance(id: "personal")
        #expect(work.id != personal.id)
        #expect(work.protocolKind == personal.protocolKind)
        #expect(work.authStyle == .anthropicKey)
    }

    @Test func importedConfigurationCannotEmbedCredentialsInURL() {
        let template = FamiliarProviderCatalog.deepSeek
        let credentialURL = URL(string: "https://username:secret@example.com/v1")!
        #expect(throws: (any Error).self) {
            try FamiliarProviderInstanceStore.validate(template.instance(id: "test", url: credentialURL))
        }
    }

    @Test func anthropicToolsUseNativeBlocks() async throws {
        let descriptor = FamiliarProviderCatalog.templates.first { $0.id == "anthropic" }!
        let provider = FamiliarStructuredModelProvider(descriptor: descriptor, apiKey: "unused")
        let request = FamiliarModelRequest(model: "test", messages: [
            .system("System instructions"),
            .user("Question"),
            .assistant(nil, toolCalls: [.init(id: "call-1", name: "lookup", arguments: "{\"q\":\"hello\"}")]),
            .tool("{\"ok\":true}", toolCallID: "call-1", name: "lookup")
        ], tools: [])
        let body = try await provider.requestBody(request)
        let messages = try #require(body["messages"] as? [[String: Any]])
        #expect(body["system"] as? String == "System instructions")
        let call = (messages[1]["content"] as? [[String: Any]])?.first
        let result = (messages[2]["content"] as? [[String: Any]])?.first
        #expect(call?["type"] as? String == "tool_use")
        #expect(result?["tool_use_id"] as? String == "call-1")
    }

    @Test func responsesToolResultsKeepCallIdentity() async throws {
        let descriptor = FamiliarProviderCatalog.templates.first { $0.id == "responses" }!
        let body = try await FamiliarStructuredModelProvider(descriptor: descriptor, apiKey: "unused").requestBody(.init(model: "test", messages: [
            .assistant(nil, toolCalls: [.init(id: "c1", name: "lookup", arguments: "{}")]),
            .tool("done", toolCallID: "c1", name: "lookup")
        ], tools: []))
        let input = try #require(body["input"] as? [[String: Any]])
        #expect(input[0]["call_id"] as? String == "c1")
        #expect(input[1]["type"] as? String == "function_call_output")
        #expect(input[1]["call_id"] as? String == "c1")
        #expect(body["store"] as? Bool == false)
    }

    @Test func deviceFlowDistinguishesPollingFromFailure() {
        #expect(FamiliarKimiDeviceFlow.classifyPoll(json: ["error": "authorization_pending"], httpOK: false) == .pending)
        #expect(FamiliarKimiDeviceFlow.classifyPoll(json: ["error": "slow_down"], httpOK: false) == .slowDown)
        #expect(FamiliarKimiDeviceFlow.bumpedInterval(5) == 10)
        #expect(FamiliarKimiDeviceFlow.classifyPoll(json: ["error": "access_denied"], httpOK: false) == .denied("access_denied"))
    }

    @Test @MainActor func importedVoiceURLJoiningAvoidsDuplicateVersion() {
        let voice = FamiliarVoiceProvider(providerId: "test", baseURL: "https://example.com/v1", apiKey: nil)
        #expect(voice.composedURLString(path: "/v1/audio/speech") == "https://example.com/v1/audio/speech")
    }
}

private actor FamiliarGroupProbe {
    var calls: [String] = []
    func record(_ id: String) { calls.append(id) }
}

private struct FamiliarGroupTestProvider: FamiliarModelProvider {
    let providerID: String
    let probe: FamiliarGroupProbe
    let fail: Bool
    let emitBeforeFailure: Bool
    func stream(request: FamiliarModelRequest) -> AsyncThrowingStream<FamiliarModelStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                await probe.record(providerID)
                if emitBeforeFailure { continuation.yield(.textDelta("partial")) }
                if fail { continuation.finish(throwing: FamiliarProviderRequestError.server(provider: providerID, statusCode: 429, message: "limited")) }
                else { continuation.yield(.textDelta("done")); continuation.yield(.completed(.stop)); continuation.finish() }
            }
        }
    }
}

@Suite("Imported model group boundaries")
struct FamiliarGroupBoundaryTests {
    @Test func fallbackOnlyBeforeOutput() async throws {
        let probe = FamiliarGroupProbe()
        let first = FamiliarGroupTestProvider(providerID: "first", probe: probe, fail: true, emitBeforeFailure: false)
        let second = FamiliarGroupTestProvider(providerID: "second", probe: probe, fail: false, emitBeforeFailure: false)
        let provider = FamiliarGroupModelProvider(providerID: "group", members: [.init(provider: first, modelID: "a"), .init(provider: second, modelID: "b")], strategy: "fallback", fallbackOnAnyError: false, sessionID: "chat")
        let response = try await provider.generate(request: .init(model: "group", messages: [.user("hello")], tools: []))
        #expect(response.text == "done")
        #expect(await probe.calls == ["first", "second"])
    }

    @Test func partialOutputNeverRetriesAnotherProvider() async {
        let probe = FamiliarGroupProbe()
        let first = FamiliarGroupTestProvider(providerID: "first", probe: probe, fail: true, emitBeforeFailure: true)
        let second = FamiliarGroupTestProvider(providerID: "second", probe: probe, fail: false, emitBeforeFailure: false)
        let provider = FamiliarGroupModelProvider(providerID: "group", members: [.init(provider: first, modelID: "a"), .init(provider: second, modelID: "b")], strategy: "fallback", fallbackOnAnyError: true, sessionID: "chat")
        do { _ = try await provider.generate(request: .init(model: "group", messages: [.user("hello")], tools: [])); Issue.record("Expected an interrupted response") }
        catch { }
        #expect(await probe.calls == ["first"])
    }

    @Test func remoteToolsAlwaysProposeBeforeCalling() async throws {
        let config = FamiliarMCPConfiguration(id: UUID(), name: "External", endpoint: URL(string: "https://example.com/mcp")!, token: nil)
        let definition = FamiliarMCPToolDefinition(name: "update", description: "Update external data", inputSchema: .init(type: .object))
        let tool = FamiliarMCPTool(definition: definition, configuration: config, client: FamiliarMCPClient(configuration: config))
        let context = FamiliarToolContext(runID: "test", toolCallID: "call")
        let assessment = try await tool.preflight(.object([:]), context: context)
        #expect(assessment.disposition == .requiresApproval)
        let result = try await tool.execute(.object([:]), context: context)
        guard case .action(let proposal) = result else { Issue.record("Expected a proposal"); return }
        #expect(proposal.allowedAuthorizationDurations == [.once])
        #expect(proposal.undoPolicy == .unavailable)
        #expect(proposal.idempotencyKey == context.idempotencyKey)
        #expect(proposal.fields.first(where: { $0.id == "method" })?.value == "update")
    }
}
