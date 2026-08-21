import CoreSpotlight
import Foundation
import SwiftData
import Testing
@testable import Familiar

@Suite("Familiar baseline")
struct FamiliarBaselineTests {
    @Test("App dependencies register the current seventeen tools")
    @MainActor
    func registeredToolNames() async {
        let dependencies = FamiliarAppDependencies()
        let manifests = await dependencies.registry.snapshot()
        let names = manifests.map(\.name)
        #expect(names == [
            "app_information",
            "artifact_edit",
            "artifact_write",
            "ask_user",
            "calendar_events",
            "create_calendar_event",
            "create_reminder",
            "current_date_time",
            "present_insight",
            "present_recommendation",
            "reminders",
            "resource_list",
            "resource_read",
            "resource_search",
            "task_plan",
            "web_fetch",
            "web_search"
        ])
    }

    @Test("Provider catalog has stable unique identifiers")
    func providerCatalogIdentifiersAreUnique() {
        let identifiers = FamiliarProviderCatalog.builtIn.map(\.id)
        #expect(identifiers.count == 12)
        #expect(Set(identifiers).count == identifiers.count)
        #expect(!identifiers.contains(FamiliarProviderCatalog.customProviderID))
    }

    @Test("Unknown models use the safe text-only capability fallback")
    func unknownModelsAreTextOnly() {
        let model = FamiliarProviderCatalog.deepSeek.model(for: "future-model")
        #expect(model.capabilities.supportsText)
        #expect(!model.capabilities.supportsTools)
        #expect(!model.capabilities.supportsImages)
        #expect(!model.capabilities.supportsDocuments)
    }

    @Test("Markdown newlines are normalized")
    func markdownNormalizesNewlines() {
        #expect(FamiliarMarkdownNormalizer.normalize("a\r\nb\rc") == "a\nb\nc")
    }

    @Test("Markdown CSP blocks automatic remote image requests")
    @MainActor func markdownRemoteImagePolicy() {
        let directives = Dictionary(
            uniqueKeysWithValues: FamiliarMarkdownHTML.contentSecurityPolicy
                .split(separator: ";")
                .compactMap { directive -> (String, [Substring])? in
                    let tokens = directive.split(whereSeparator: \.isWhitespace)
                    guard let name = tokens.first else { return nil }
                    return (String(name), Array(tokens.dropFirst()))
                }
        )

        #expect(directives["img-src"] == ["'self'", "data:"])
        #expect(directives["connect-src"] == ["'none'"])
        #expect(!FamiliarMarkdownHTML.baseDocument.contains("img-src https:"))
    }

    @Test("Conversation links open only web destinations in app")
    func conversationLinkRouting() throws {
        #expect(FamiliarConversationURLRouter.shouldOpenInApp(try #require(URL(string: "https://example.com/path"))))
        #expect(FamiliarConversationURLRouter.shouldOpenInApp(try #require(URL(string: "HTTP://example.com"))))
        #expect(!FamiliarConversationURLRouter.shouldOpenInApp(try #require(URL(string: "mailto:hello@example.com"))))
        #expect(!FamiliarConversationURLRouter.shouldOpenInApp(try #require(URL(string: "https:///missing-host"))))
        #expect(!FamiliarConversationURLRouter.shouldOpenInApp(try #require(URL(string: "file:///tmp/page.html"))))
    }

    @Test("Deep links accept only bounded typed routes")
    func deepLinkParsing() throws {
        let conversationID = UUID()
        let runID = UUID()
        #expect(
            FamiliarDeepLink(url: try #require(URL(string: "familiar://new?text=Hello%20Familiar")))
                == .newDraft(text: "Hello Familiar")
        )
        #expect(
            FamiliarDeepLink(url: try #require(URL(string: "familiar://conversation/\(conversationID.uuidString)")))
                == .conversation(conversationID)
        )
        #expect(
            FamiliarDeepLink(url: try #require(URL(string: "familiar://run/\(runID.uuidString)")))
                == .run(runID)
        )
        #expect(FamiliarDeepLink(url: try #require(URL(string: "https://example.com/new"))) == nil)
        #expect(FamiliarDeepLink(url: try #require(URL(string: "familiar://conversation/not-a-uuid"))) == nil)

        let oversized = String(repeating: "x", count: FamiliarDeepLink.maximumPrefillCharacters + 1)
        let encoded = try #require(oversized.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed))
        let bounded = FamiliarDeepLink(url: try #require(URL(string: "familiar://new?text=\(encoded)")))
        #expect(bounded == .newDraft(text: String(oversized.prefix(FamiliarDeepLink.maximumPrefillCharacters))))
    }

    @Test("Deep links resolve conversation and run context") @MainActor
    func deepLinkRouting() throws {
        let container = try FamiliarTestStore.make()
        let first = FamiliarConversation(title: "First")
        let second = FamiliarConversation(title: "Second")
        let runID = UUID()
        let run = FamiliarAgentRun(runtimeID: runID.uuidString, status: .completed, conversation: second)
        container.mainContext.insert(first)
        container.mainContext.insert(second)
        container.mainContext.insert(run)
        try container.mainContext.save()

        let conversations = try container.mainContext.fetch(FetchDescriptor<FamiliarConversation>())
        let controller = FamiliarChatController(dependencies: FamiliarAppDependencies())
        #expect(controller.openDeepLink(.conversation(first.id), conversations: conversations, in: container.mainContext))
        #expect(controller.selectedConversationID == first.id)
        #expect(controller.openDeepLink(.run(runID), conversations: conversations, in: container.mainContext))
        #expect(controller.selectedConversationID == second.id)
        #expect(controller.openDeepLink(.newDraft(text: "Draft"), conversations: conversations, in: container.mainContext))
        #expect(controller.selectedConversationID == nil)
        #expect(controller.draft == "Draft")
    }

    @Test("App Intents create bounded typed foreground handoffs") @MainActor
    func appIntentHandoff() async throws {
        let handoff = FamiliarAppIntentHandoff.shared
        _ = handoff.takePendingRequest()

        let emptyAsk = AskFamiliarIntent()
        emptyAsk.question = "   "
        _ = try await emptyAsk.perform()
        #expect(handoff.pendingRequest == nil)

        let oversized = String(repeating: "x", count: FamiliarDeepLink.maximumPrefillCharacters + 1)
        let ask = AskFamiliarIntent()
        ask.question = "  \(oversized)  "
        _ = try await ask.perform()
        let askRequest = try #require(handoff.takePendingRequest())
        #expect(askRequest.automaticallySubmit)
        #expect(askRequest.deepLink == .newDraft(text: String(oversized.prefix(FamiliarDeepLink.maximumPrefillCharacters))))

        let process = ProcessWithFamiliarIntent()
        process.text = "Process this"
        _ = try await process.perform()
        let processRequest = try #require(handoff.takePendingRequest())
        #expect(processRequest.automaticallySubmit)
        #expect(processRequest.deepLink == .newDraft(text: "Process this"))

        let existing = FamiliarSystemEntryRequest.deepLink(.newDraft(text: "Keep me"))
        handoff.submit(existing)
        _ = try await OpenFamiliarIntent().perform()
        #expect(handoff.takePendingRequest() == existing)
    }

    @Test("Notification routes preserve local conversation and run identifiers")
    @MainActor
    func notificationRoutes() {
        let conversationID = UUID()
        let runID = UUID()

        let conversation = FamiliarNotificationRoute.conversation(conversationID)
        let run = FamiliarNotificationRoute.run(runID)
        #expect(FamiliarNotificationRoute(encodedValue: conversation.encodedValue) == conversation)
        #expect(FamiliarNotificationRoute(encodedValue: run.encodedValue) == run)
        #expect(conversation.deepLink == .conversation(conversationID))
        #expect(run.deepLink == .run(runID))
        #expect(FamiliarNotificationService.route(from: [
            FamiliarNotificationService.routeUserInfoKey: run.encodedValue
        ]) == run)
        #expect(FamiliarNotificationService.route(from: [:]) == nil)
        #expect(FamiliarNotificationRoute(encodedValue: "run:not-a-uuid") == nil)
        #expect(FamiliarNotificationRoute(encodedValue: "unknown:\(runID.uuidString)") == nil)
    }

    @Test("Spotlight conversation items contain only bounded local metadata and typed routes")
    @MainActor
    func spotlightConversationItems() {
        let id = UUID()
        let updatedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let conversation = FamiliarSpotlightConversation(
            id: id,
            title: "  " + String(repeating: "L", count: FamiliarSpotlightIndexer.maximumTitleCharacters + 1) + "  ",
            updatedAt: updatedAt
        )
        let item = FamiliarSpotlightIndexer.searchableItem(for: conversation)

        #expect(item.uniqueIdentifier == "conversation:\(id.uuidString)")
        #expect(item.domainIdentifier == FamiliarSpotlightIndexer.domainIdentifier)
        #expect(item.attributeSet.title == String(repeating: "L", count: FamiliarSpotlightIndexer.maximumTitleCharacters))
        #expect(item.attributeSet.metadataModificationDate == updatedAt)
        #expect(item.attributeSet.contentDescription == String(localized: "spotlight.conversation.description"))

        let activity = NSUserActivity(activityType: CSSearchableItemActionType)
        activity.userInfo = [CSSearchableItemActivityIdentifier: conversation.searchableIdentifier]
        #expect(FamiliarSpotlightIndexer.deepLink(from: activity) == .conversation(id))
        #expect(FamiliarSpotlightIndexer.deepLink(forSearchableIdentifier: "conversation:not-a-uuid") == nil)
        #expect(FamiliarSpotlightIndexer.deepLink(forSearchableIdentifier: "run:\(id.uuidString)") == nil)
    }

    @Test("Shared inbox stores bounded text and verified file copies")
    func sharedInboxRoundTrip() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FamiliarSharedInboxTests-\(UUID().uuidString)", isDirectory: true)
        let source = root.appendingPathComponent("source.txt", isDirectory: false)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("shared document".utf8).write(to: source)
        defer { try? FileManager.default.removeItem(at: root) }

        let oversizedText = String(repeating: "x", count: FamiliarSharedInbox.maximumTextCharacters + 1)
        let id = try FamiliarSharedInbox.enqueue(text: oversizedText, fileURLs: [source], rootURL: root)
        let item = try #require(FamiliarSharedInbox.pendingItems(rootURL: root).first)
        #expect(item.payload.id == id)
        #expect(item.payload.text.count == FamiliarSharedInbox.maximumTextCharacters)
        #expect(item.payload.files.map(\.originalName) == ["source.txt"])
        #expect(try Data(contentsOf: #require(item.fileURLs.first)) == Data("shared document".utf8))

        let symbolicLink = root.appendingPathComponent("source-link.txt", isDirectory: false)
        try FileManager.default.createSymbolicLink(at: symbolicLink, withDestinationURL: source)
        #expect(throws: FamiliarSharedInboxError.self) {
            try FamiliarSharedInbox.enqueue(text: "", fileURLs: [symbolicLink], rootURL: root)
        }

        FamiliarSharedInbox.remove(item)
        #expect(try FamiliarSharedInbox.pendingItems(rootURL: root).isEmpty)
    }

    @Test("Shared inbox rejects traversal in a tampered manifest")
    func sharedInboxRejectsTraversal() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FamiliarSharedInboxTamperTests-\(UUID().uuidString)", isDirectory: true)
        let payloadID = UUID()
        let payloadDirectory = root
            .appendingPathComponent("ShareInbox", isDirectory: true)
            .appendingPathComponent(payloadID.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: payloadDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let payload = FamiliarSharedInboxPayload(
            id: payloadID,
            createdAt: Date(),
            text: "",
            files: [.init(storedName: "../escape.txt", originalName: "escape.txt", byteSize: 1)]
        )
        try JSONEncoder().encode(payload).write(
            to: payloadDirectory.appendingPathComponent("manifest.json"),
            options: .atomic
        )

        #expect(throws: FamiliarSharedInboxError.self) {
            try FamiliarSharedInbox.pendingItems(rootURL: root)
        }
        #expect(!FileManager.default.fileExists(atPath: payloadDirectory.path))
    }

    @Test("Shared inbox documents enter the existing attachment pipeline")
    func sharedInboxAttachmentPipeline() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FamiliarSharedDraftImportTests-\(UUID().uuidString)", isDirectory: true)
        let source = root.appendingPathComponent("notes.txt", isDirectory: false)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("shared attachment body".utf8).write(to: source)
        defer { try? FileManager.default.removeItem(at: root) }

        try FamiliarSharedInbox.enqueue(text: "Review this", fileURLs: [source], rootURL: root)
        let prepared = try #require(await FamiliarSharedDraftImportService.prepareNext(rootURL: root))
        #expect(prepared.text == "Review this")
        #expect(prepared.attachments.count == 1)
        #expect(prepared.attachments.first?.extractedText.contains("shared attachment body") == true)
        #expect(prepared.firstImportErrorDescription == nil)

        FamiliarSharedDraftImportService.consume(prepared)
        FamiliarSharedDraftImportService.discardPreparedAttachments(prepared)
        #expect(try FamiliarSharedInbox.pendingItems(rootURL: root).isEmpty)
    }

    @Test("SSE fixtures preserve OpenAI, Anthropic and Gemini framing")
    func sseFixtures() {
        let openAI = FamiliarSSEParser.events(in: "data: {\"choices\":[]}\n\ndata: [DONE]\n\n")
        let anthropic = FamiliarSSEParser.events(in: "event: content_block_delta\ndata: {\"delta\":{\"text\":\"Hi\"}}\n\n")
        let gemini = FamiliarSSEParser.events(in: "data: {\"candidates\":[]}\n\n")
        #expect(openAI.map(\.data) == ["{\"choices\":[]}", "[DONE]"])
        #expect(anthropic.first?.name == "content_block_delta")
        #expect(gemini.first?.data == "{\"candidates\":[]}")
    }

    @Test("Attachment boundaries reject traversal")
    func attachmentBoundaries() {
        #expect(FamiliarAttachmentStore.maximumSourceBytes == 25 * 1024 * 1024)
        #expect(FamiliarAttachmentStore.isSafeRelativePath("Messages/id/file.pdf"))
        #expect(!FamiliarAttachmentStore.isSafeRelativePath("../secret"))
        #expect(!FamiliarAttachmentStore.isSafeRelativePath("/private/secret"))
        #expect(!FamiliarAttachmentStore.isSafeRelativePath("Messages//file.pdf"))
    }

    @Test("Execution policy confirms natural-language writes")
    func executionPolicy() {
        let manifest = FamiliarToolManifest(name: "write", title: "Write", description: "", parameters: .init(type: .object), effect: .reversibleWrite, risk: .low, requirements: [])
        let policy = FamiliarExecutionPolicy()
        #expect(policy.decide(manifest: manifest, availability: .available, idempotencyKey: "run:call") == .requestApproval)
        let token = FamiliarOneShotAuthorization(toolName: "write", idempotencyKey: "run:call", source: .appIntent)
        #expect(policy.decide(manifest: manifest, availability: .available, authorization: token, idempotencyKey: "run:call") == .requestApproval)
        let grant = FamiliarAuthorizationGrant(id: UUID(), userAction: "confirm", source: .builtIn, capabilityID: manifest.id, capabilityVersion: manifest.version, argumentsHash: FamiliarAuthorizationGrant.argumentsHash("{}"), projectID: nil, expiresAt: Date().addingTimeInterval(60), singleUse: true, evidence: "fixture", consumedAt: nil, state: .issued)
        #expect(policy.decide(manifest: manifest, availability: .available, grant: grant, arguments: "{}", projectID: nil) == .execute)
    }

    @Test("Run and activity projection persist in the in-memory store") @MainActor
    func runActivityPersistence() throws {
        let container = try FamiliarTestStore.make()
        let conversation = FamiliarConversation()
        let run = FamiliarAgentRun(runtimeID: "run", status: .completed, conversation: conversation)
        run.finishedAt = Date(timeIntervalSince1970: 10)
        let activity = FamiliarActivityRecord(activityID: "tool:run:call", runtimeID: "run", assistantTurnID: "turn", kind: .tool, effect: .read, phase: .succeeded, toolName: "tool", toolCallID: "call", summary: "Tool", detail: "Done", sequence: 1, startedAt: .distantPast, endedAt: .distantFuture)
        container.mainContext.insert(conversation)
        container.mainContext.insert(run)
        container.mainContext.insert(activity)
        try container.mainContext.save()
        #expect(try container.mainContext.fetch(FetchDescriptor<FamiliarAgentRun>()).count == 1)
        #expect(try container.mainContext.fetch(FetchDescriptor<FamiliarActivityRecord>()).first?.activityID == "tool:run:call")
    }

    @Test("Cancelling a run resolves a pending confirmation once")
    func confirmationCancellationIsIdempotent() async throws {
        let coordinator = FamiliarToolConfirmationCoordinator()
        let request = FamiliarToolConfirmationRequest(
            runID: "run",
            toolCallID: "call",
            toolName: "test",
            title: "Test"
        )
        let waiting = Task {
            try await coordinator.requestConfirmation(request)
        }

        while await coordinator.pendingRequests().isEmpty {
            await Task.yield()
        }
        #expect(await coordinator.cancel(runID: "run") == 1)
        #expect(try await waiting.value == .cancelled)
        #expect(
            await coordinator.resolve(requestID: request.id, decision: .confirmed)
                == .alreadyResolved(.cancelled)
        )
    }

    @Test("Store recovery removes the current store and all local content") @MainActor
    func storeRecovery() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }

        let persistence = root.appendingPathComponent("Familiar/Persistence", isDirectory: true)
        let attachments = root.appendingPathComponent("Familiar/Attachments", isDirectory: true)
        let projectResources = root.appendingPathComponent("Familiar/ProjectResources", isDirectory: true)
        let artifacts = root.appendingPathComponent("Familiar/Artifacts", isDirectory: true)
        try fileManager.createDirectory(at: persistence, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: attachments, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: projectResources, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: artifacts, withIntermediateDirectories: true)
        try Data("store".utf8).write(to: persistence.appendingPathComponent(FamiliarModelContainer.storeFilename))
        try Data("wal".utf8).write(to: persistence.appendingPathComponent(FamiliarModelContainer.storeFilename + "-wal"))
        try Data("old".utf8).write(to: persistence.appendingPathComponent("FamiliarAgentV1.store"))
        try Data("attachment".utf8).write(to: attachments.appendingPathComponent("message.txt"))
        try Data("resource".utf8).write(to: projectResources.appendingPathComponent("resource.txt"))
        try Data("artifact".utf8).write(to: artifacts.appendingPathComponent("artifact.txt"))

        try FamiliarApp.resetStore(in: root, fileManager: fileManager)

        #expect(!fileManager.fileExists(atPath: persistence.appendingPathComponent(FamiliarModelContainer.storeFilename).path))
        #expect(!fileManager.fileExists(atPath: persistence.appendingPathComponent(FamiliarModelContainer.storeFilename + "-wal").path))
        #expect(fileManager.fileExists(atPath: persistence.appendingPathComponent("FamiliarAgentV1.store").path))
        #expect(!fileManager.fileExists(atPath: attachments.path))
        #expect(!fileManager.fileExists(atPath: projectResources.path))
        #expect(!fileManager.fileExists(atPath: artifacts.path))
    }
}
