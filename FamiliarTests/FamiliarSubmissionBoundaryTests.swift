import Foundation
import SwiftData
import Testing
import UIKit
@testable import Familiar

@Suite("Submission cleanup and credential boundaries", .serialized)
struct FamiliarSubmissionBoundaryTests {
    @Test("Groups need a real member credential; a key on the group itself is not authority")
    func groupCredentials() {
        let member = FamiliarProviderCatalog.deepSeek.instance(id: "member")
        var group = FamiliarProviderCatalog.deepSeek.instance(id: "group")
        group.routes = [.init(provider: member, modelID: member.defaultModel.id)]
        #expect(FamiliarProviderFactory.credential(for: group, lookup: { _ in nil }) == nil)
        #expect(FamiliarProviderFactory.credential(for: group, lookup: { $0 == "group" ? "irrelevant-group-key" : nil }) == nil)
        #expect(FamiliarProviderFactory.credential(for: group, lookup: { $0 == "member" ? "   " : nil }) == nil)
        #expect(FamiliarProviderFactory.credential(for: group, lookup: { $0 == "member" ? "member-token" : nil }) == "")
        group.routes = []
        #expect(FamiliarProviderFactory.credential(for: group, lookup: { _ in "token" }) == nil)
        #expect(FamiliarProviderFactory.credential(for: member, lookup: { _ in " token " }) == "token")
    }

    @Test("A group with no usable members rejects before consuming text, files, images or Skill selection")
    @MainActor
    func keylessGroupKeepsDraft() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("KeylessGroup-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("draft.txt")
        try Data("Retained draft bytes".utf8).write(to: source)
        let attachment = try await FamiliarAttachmentStore.importDocument(from: source)
        defer { FamiliarAttachmentStore.remove(relativePath: attachment.relativePath) }
        let originalProfiles = UserDefaults.standard.object(forKey: "familiar.provider.instances.v1")
        let originalGroups = UserDefaults.standard.object(forKey: "familiar.model.groups.v1")
        defer {
            for (key, value) in [("familiar.provider.instances.v1", originalProfiles), ("familiar.model.groups.v1", originalGroups)] {
                if let value { UserDefaults.standard.set(value, forKey: key) }
                else { UserDefaults.standard.removeObject(forKey: key) }
            }
        }
        let member = FamiliarProviderCatalog.deepSeek.instance(id: "keyless-" + UUID().uuidString)
        try FamiliarProviderInstanceStore.save(member)
        let group = FamiliarModelGroup(name: "No credentials", members: [.init(providerID: member.id, modelID: member.defaultModel.id)])
        try FamiliarModelGroupStore.save(group)
        let descriptor = try #require(FamiliarProviderCatalog.descriptor(for: group.id))
        #expect(!FamiliarKeychainStore.isConfigured(for: group.id))
        let container = try FamiliarTestStore.make(name: "KeylessGroupDraft")
        let project = FamiliarProject(name: "Draft")
        container.mainContext.insert(project)
        try container.mainContext.save()
        let controller = FamiliarChatController(dependencies: .init())
        controller.settings.providerID = group.id
        controller.settings.modelID = descriptor.defaultModel.id
        controller.selectedProjectID = project.id
        controller.selectedSkillID = UUID()
        let skill = controller.selectedSkillID
        controller.draft = "  Retain this draft  "
        controller.draftAttachments = [attachment]
        let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { _ in }
        controller.draftImages = [FamiliarDraftImage(image: image)]
        let images = controller.draftImages.map(\.id)
        controller.startSending(in: container.mainContext)
        #expect(!controller.isSending)
        #expect(controller.errorMessage != nil)
        #expect(controller.draft == "  Retain this draft  ")
        #expect(controller.draftAttachments == [attachment])
        #expect(controller.draftImages.map(\.id) == images)
        #expect(controller.selectedSkillID == skill)
        #expect(FamiliarAttachmentStore.url(for: attachment.relativePath) != nil)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<FamiliarConversation>()) == 0)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<FamiliarMessage>()) == 0)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<FamiliarAttachment>()) == 0)
    }

    @Test("A cancelled document import never consumes its borrowed source")
    func cancelledImport() async throws {
        let source = FileManager.default.temporaryDirectory.appendingPathComponent("CancelledImport-\(UUID().uuidString).txt")
        let bytes = Data("Borrowed original".utf8)
        try bytes.write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await FamiliarAttachmentStore.importDocument(from: source)
        }
        await #expect(throws: CancellationError.self) { _ = try await task.value }
        #expect(try Data(contentsOf: source) == bytes)
    }

    @Test("Recovery invoked by a reappearing view cannot terminate active send or compaction")
    @MainActor
    func activeRecoveryIsBlocked() throws {
        let container = try FamiliarTestStore.make(name: "ActiveRecovery")
        let context = container.mainContext
        let chat = FamiliarConversation()
        let run = FamiliarAgentRun(runtimeID: "active", status: .running, conversation: chat)
        context.insert(chat)
        context.insert(run)
        try context.save()
        let controller = FamiliarChatController(dependencies: .init())
        controller.isSending = true
        controller.recoverInterruptedRuns(in: context)
        #expect(run.status == .running)
        controller.isSending = false
        controller.isCompacting = true
        controller.recoverInterruptedRuns(in: context)
        #expect(run.status == .running)
        controller.isCompacting = false
        controller.recoverInterruptedRuns(in: context)
        #expect(run.status == .failed)
    }

    @Test("Failed file commit leaves the draft copy and original bytes intact")
    func failedAttachmentCommit() async throws {
        let source = FileManager.default.temporaryDirectory.appendingPathComponent("AttachmentCommit-\(UUID().uuidString).txt")
        let bytes = Data("Original and draft".utf8)
        try bytes.write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }
        let draft = try await FamiliarAttachmentStore.importDocument(from: source)
        let messageID = UUID()
        let path = FamiliarAttachmentStore.committedRelativePath(of: draft, messageID: messageID)
        defer { FamiliarAttachmentStore.remove(relativePaths: [draft.relativePath, path]) }
        _ = try FamiliarAttachmentStore.committedCopy(of: draft, messageID: messageID)
        #expect(throws: FamiliarAttachmentStoreError.self) { _ = try FamiliarAttachmentStore.committedCopy(of: draft, messageID: messageID) }
        let staged = try #require(FamiliarAttachmentStore.url(for: draft.relativePath))
        #expect(try Data(contentsOf: staged) == bytes)
        #expect(try Data(contentsOf: source) == bytes)
        let committed = try #require(FamiliarAttachmentStore.url(for: path))
        #expect(try Data(contentsOf: committed) == bytes)
    }
}
