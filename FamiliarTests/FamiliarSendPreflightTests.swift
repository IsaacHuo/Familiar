import Foundation
import SwiftData
import Testing
import UIKit
@testable import Familiar

@Suite("Send context preflight")
struct FamiliarSendPreflightTests {
    private let settings = FamiliarSettings.defaultValue
    private var maximum: Int { settings.selectedModel.capabilities.maximumInputCharacters }

    @Test("Protected Project resources cannot be truncated to submit a message")
    func protectedOverflow() {
        #expect(throws: FamiliarAgentError.self) {
            _ = try assemble(resources: [resource(count: maximum + 1)], messages: [message("Hello")])
        }
    }

    @Test("Project and pending document must fit together, even when each fits alone")
    func combinedDocumentOverflow() throws {
        let resources = [resource(count: maximum * 3 / 5)]
        let pending = message("Review this", attachments: [attachment(text: String(repeating: "d", count: maximum * 3 / 5))])
        try FamiliarProjectContextAssembler.validateSubmission(assemble(resources: resources, messages: [message("Hello")]))
        try FamiliarProjectContextAssembler.validateSubmission(assemble(messages: [pending]))
        let combined = try assemble(resources: resources, messages: [pending])
        #expect(throws: FamiliarAgentError.self) { try FamiliarProjectContextAssembler.validateSubmission(combined) }
    }

    @Test("Old history stays eligible for compaction instead of rejecting the pending turn")
    func historyCanCompact() throws {
        let snapshot = try assemble(messages: [message(String(repeating: "h", count: maximum * 2)), message("Continue", sequence: 1)])
        #expect(snapshot.initialInputCharacters > maximum)
        try FamiliarProjectContextAssembler.validateSubmission(snapshot)
    }

    @Test("Base tool parameters are part of the minimum submission budget")
    func baseSchemaOverflow() throws {
        let manifest = FamiliarToolManifest(name: "tools_load", title: "Load", description: "Fixture",
            parameters: .init(type: .object, properties: ["groups": .init(type: .string, description: String(repeating: "s", count: maximum * 3 / 5))]),
            effect: .read, risk: .low)
        let pending = message(String(repeating: "p", count: maximum * 3 / 5))
        try FamiliarProjectContextAssembler.validateSubmission(assemble(messages: [message("Hello")], tools: [manifest]))
        try FamiliarProjectContextAssembler.validateSubmission(assemble(messages: [pending]))
        let combined = try assemble(messages: [pending], tools: [manifest])
        #expect(combined.toolManifests.map(\.name) == ["tools_load"])
        #expect(throws: FamiliarAgentError.self) { try FamiliarProjectContextAssembler.validateSubmission(combined) }
    }

    @Test("Vision evidence is checked again after recognition and retains the final attachment identity")
    func visionEvidenceOverflow() throws {
        #expect(!settings.selectedModel.capabilities.supportsImages)
        let image = attachment(kind: .image)
        let pending = message("Read this image", attachments: [image])
        let resources = [resource(count: maximum - 12_000)]
        try FamiliarProjectContextAssembler.validateSubmission(assemble(resources: resources, messages: [pending]))
        let evidence = FamiliarVisualEvidence(id: UUID(), attachmentID: image.id, filename: image.filename,
            sourceRelativePath: image.relativePath, renderedText: String(repeating: "v", count: 20_000),
            processingMethod: "fixture", engineVersion: "1", createdAt: Date())
        let final = try assemble(resources: resources, messages: [pending], evidence: [evidence])
        #expect(final.visualEvidenceMessageID == pending.id)
        #expect(final.visualEvidence.first?.sourceRelativePath == final.attachments.first?.relativePath)
        #expect(throws: FamiliarAgentError.self) { try FamiliarProjectContextAssembler.validateSubmission(final) }
    }

    @Test("A document path can be frozen before copying and equals the later committed path")
    func attachmentPathBeforeCommit() async throws {
        let source = FileManager.default.temporaryDirectory.appendingPathComponent("Preflight-\(UUID().uuidString).txt")
        try Data("Draft bytes".utf8).write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }
        let draft = try await FamiliarAttachmentStore.importDocument(from: source)
        let messageID = UUID()
        let path = FamiliarAttachmentStore.committedRelativePath(of: draft, messageID: messageID)
        defer { FamiliarAttachmentStore.remove(relativePaths: [draft.relativePath, path]) }
        #expect(FamiliarAttachmentStore.url(for: path) == nil)
        let input = FamiliarAttachmentSnapshot(id: draft.id, kind: draft.kind, filename: draft.filename, mimeType: draft.mimeType,
            relativePath: path, extractedText: draft.extractedText, byteSize: draft.byteSize, extractionEngine: draft.extractionEngine,
            extractionVersion: draft.extractionVersion, detectedFormat: draft.detectedFormat, usedOCR: draft.usedOCR)
        let snapshot = try assemble(messages: [message("Read", attachments: [input])])
        try FamiliarProjectContextAssembler.validateSubmission(snapshot)
        #expect(snapshot.attachments.first?.relativePath == path)
        #expect(try FamiliarAttachmentStore.committedCopy(of: draft, messageID: messageID) == path)
        let committedURL = try #require(FamiliarAttachmentStore.url(for: path))
        #expect(try Data(contentsOf: committedURL) == Data("Draft bytes".utf8))
    }

    @Test("Supported image input fails explicitly when its bytes are unavailable")
    func missingImageFails() {
        var visionSettings = settings
        visionSettings.providerID = "codex"
        visionSettings.modelID = FamiliarProviderCatalog.descriptor(for: "codex")!.defaultModel.id
        #expect(visionSettings.selectedModel.capabilities.supportsImages)
        #expect(throws: FamiliarVisionProcessorError.self) {
            _ = try FamiliarProjectContextAssembler.assemble(seed: seed(), settings: visionSettings,
                messages: [message("Read", attachments: [attachment(kind: .image)])], toolManifests: [])
        }
    }

    @Test("Image bytes are read from the draft while its frozen path already points to the committed identity")
    @MainActor
    func stagedImageReadPath() throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { renderer in
            UIColor.white.setFill()
            renderer.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        let draft = try FamiliarAttachmentStore.importImage(image)
        defer { FamiliarAttachmentStore.remove(relativePath: draft.relativePath) }
        let path = FamiliarAttachmentStore.committedRelativePath(of: draft, messageID: UUID())
        let input = FamiliarAttachmentSnapshot(id: draft.id, kind: draft.kind, filename: draft.filename, mimeType: draft.mimeType,
            relativePath: path, extractedText: "", byteSize: draft.byteSize, extractionEngine: draft.extractionEngine,
            extractionVersion: draft.extractionVersion, detectedFormat: draft.detectedFormat, usedOCR: draft.usedOCR)
        var visionSettings = settings
        visionSettings.providerID = "codex"
        visionSettings.modelID = FamiliarProviderCatalog.descriptor(for: "codex")!.defaultModel.id
        let snapshot = try FamiliarProjectContextAssembler.assemble(seed: seed(), settings: visionSettings,
            messages: [message("Read", attachments: [input])], toolManifests: [], attachmentReadPaths: [draft.id: draft.relativePath])
        try FamiliarProjectContextAssembler.validateSubmission(snapshot)
        #expect(snapshot.attachments.first?.relativePath == path)
        let draftURL = try #require(FamiliarAttachmentStore.url(for: draft.relativePath))
        let expectedBytes = try Data(contentsOf: draftURL)
        #expect(snapshot.providerMessages.last?.contentParts.contains(.image(data: expectedBytes, mimeType: draft.mimeType)) == true)
        #expect(FamiliarAttachmentStore.url(for: path) == nil)
    }

    @Test("Only budgeted memories advance usage and a failed submission can roll them back")
    @MainActor
    func actualMemoryUsage() throws {
        let container = try FamiliarTestStore.make(name: "MemoryPreflight")
        let context = container.mainContext
        let service = FamiliarMemoryService()
        let first = try service.insert(content: "fact " + String(repeating: "a", count: 895), scope: .global,
            projectID: nil, conversationID: nil, provenance: "fixture", creator: .user, confidence: 1, in: context)
        let overflow = try service.insert(content: "fact " + String(repeating: "b", count: 895), scope: .global,
            projectID: nil, conversationID: nil, provenance: "fixture", creator: .user, confidence: 0.9, in: context)
        let short = try service.insert(content: "Short fact", scope: .global,
            projectID: nil, conversationID: nil, provenance: "fixture", creator: .user, confidence: 0.8, in: context)
        let candidates = try service.candidates(query: "fact", projectID: nil, conversationID: nil, in: context)
        #expect(candidates.allSatisfy { $0.lastUsedAt == nil })
        let memories = candidates.map { FamiliarContextMemory(id: $0.id, scope: $0.scope, content: $0.content, provenance: $0.provenance, confidence: $0.confidence) }
        let snapshot = try assemble(messages: [message("fact")], memories: memories)
        try FamiliarProjectContextAssembler.validateSubmission(snapshot)
        #expect(snapshot.memories.map(\.id) == [first.id, short.id])
        let acceptedIDs = Set(snapshot.memories.map(\.id))
        let used = Date(timeIntervalSince1970: 5_000)
        try service.stageUsage(ids: acceptedIDs, in: context, now: used)
        #expect(context.hasChanges)
        context.rollback()
        #expect(try context.fetch(FetchDescriptor<FamiliarMemoryItem>()).allSatisfy { $0.lastUsedAt == nil })
        try service.stageUsage(ids: acceptedIDs, in: context, now: used)
        let conversation = FamiliarConversation()
        context.insert(conversation)
        context.insert(FamiliarMessage(role: .user, content: "fact", sequence: 0, conversation: conversation))
        try context.save()
        let stored = try context.fetch(FetchDescriptor<FamiliarMemoryItem>())
        #expect(stored.filter { $0.lastUsedAt == used }.map(\.id).sorted() == Array(acceptedIDs).sorted())
        #expect(stored.first { $0.id == overflow.id }?.lastUsedAt == nil)
        #expect(try context.fetchCount(FetchDescriptor<FamiliarMessage>()) == 1)
    }

    private func assemble(resources: [FamiliarContextResource] = [], messages: [FamiliarMessageSnapshot],
                          tools: [FamiliarToolManifest] = [], evidence: [FamiliarVisualEvidence] = [],
                          memories: [FamiliarContextMemory] = []) throws -> FamiliarContextSnapshot {
        try FamiliarProjectContextAssembler.assemble(seed: seed(resources: resources, memories: memories), settings: settings,
            messages: messages, toolManifests: tools, visualEvidence: evidence)
    }

    private func seed(resources: [FamiliarContextResource] = [], memories: [FamiliarContextMemory] = []) -> FamiliarProjectContextSeed {
        .init(projectID: UUID(), projectName: "Preflight", conversationID: UUID(), projectInstruction: nil, resources: resources, memories: memories)
    }

    private func resource(count: Int) -> FamiliarContextResource {
        .init(resourceID: UUID(), resourceVersionID: UUID(), version: 1, displayName: "Project.txt", filename: "Project.txt",
            mimeType: "text/plain", contentHash: "fixture", extractedText: String(repeating: "r", count: count), extractedTextHash: "fixture")
    }

    private func message(_ text: String, sequence: Int = 0, attachments: [FamiliarAttachmentSnapshot] = []) -> FamiliarMessageSnapshot {
        .init(id: UUID(), role: .user, content: text, createdAt: Date(), sequence: sequence, providerID: nil, modelID: nil, attachments: attachments)
    }

    private func attachment(kind: FamiliarAttachmentKind = .document, text: String = "") -> FamiliarAttachmentSnapshot {
        .init(id: UUID(), kind: kind, filename: kind == .image ? "Photo.jpg" : "Document.txt",
            mimeType: kind == .image ? "image/jpeg" : "text/plain", relativePath: "Messages/\(UUID().uuidString)/fixture",
            extractedText: text, byteSize: Int64(text.count), extractionEngine: "fixture", extractionVersion: "1", detectedFormat: "fixture", usedOCR: false)
    }
}
