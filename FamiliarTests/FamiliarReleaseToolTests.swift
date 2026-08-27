import Foundation
import Testing
@testable import Familiar

@MainActor
private final class FamiliarClipboardSpy: FamiliarClipboardServicing, @unchecked Sendable {
    var value: String?
    var readCount = 0
    var writes: [String?] = []

    init(value: String?) { self.value = value }

    func readText() -> String? {
        readCount += 1
        return value
    }

    func writeText(_ text: String?) {
        value = text
        writes.append(text)
    }
}

private actor FamiliarContactsFixture: FamiliarContactsServicing {
    func availability() -> FamiliarCapabilityAvailability { .available }
    func requestAccess() async throws {}
    func search(query: String, limit: Int) async throws -> [FamiliarContact] {
        [.init(id: "contact-1", displayName: "Ada", phoneNumbers: ["123"], emailAddresses: ["ada@example.com"], organizationName: "Familiar")]
    }
}

@Suite("Release tool hardening")
struct FamiliarReleaseToolTests {
    @Test("Clipboard proposals do not read or write before commit")
    @MainActor
    func clipboardCommitBoundary() async throws {
        let readSpy = FamiliarClipboardSpy(value: "private")
        let readOutcome = try await FamiliarClipboardReadTool(service: readSpy).execute(.init(), context: .init(runID: "run", toolCallID: "read"))
        guard case .action(let readProposal) = readOutcome else { Issue.record("Expected clipboard read proposal"); return }
        #expect(readSpy.readCount == 0)
        let readCommit = try await readProposal.commit()
        #expect(readSpy.readCount == 1)
        #expect(readCommit.result.modelContent.contains("private"))
        #expect(readCommit.undo == nil)

        let writeSpy = FamiliarClipboardSpy(value: "before")
        let writeOutcome = try await FamiliarClipboardWriteTool(service: writeSpy).execute(.init(text: "after"), context: .init(runID: "run", toolCallID: "write"))
        guard case .action(let writeProposal) = writeOutcome else { Issue.record("Expected clipboard write proposal"); return }
        #expect(writeSpy.readCount == 0)
        #expect(writeSpy.writes.isEmpty)
        let writeCommit = try await writeProposal.commit()
        #expect(writeSpy.readCount == 1)
        #expect(writeSpy.value == "after")
        let undo = try #require(writeCommit.undo)
        _ = try await undo()
        #expect(writeSpy.value == "before")
    }

    @Test("Contact search returns only explicitly requested fields")
    func contactFieldMinimization() async throws {
        let tool = FamiliarContactsSearchTool(service: FamiliarContactsFixture())
        let minimal = try await tool.execute(
            .init(query: "Ada", limit: nil, includePhoneNumbers: nil, includeEmailAddresses: nil, includeOrganization: nil),
            context: .init()
        )
        guard case .result(let minimalResult) = minimal else { Issue.record("Expected contact result"); return }
        #expect(minimalResult.modelContent.contains("Ada"))
        #expect(!minimalResult.modelContent.contains("123"))
        #expect(!minimalResult.modelContent.contains("ada@example.com"))

        let detailed = try await tool.execute(
            .init(query: "Ada", limit: 1, includePhoneNumbers: true, includeEmailAddresses: true, includeOrganization: true),
            context: .init()
        )
        guard case .result(let detailedResult) = detailed else { Issue.record("Expected detailed contact result"); return }
        #expect(detailedResult.modelContent.contains("123"))
        #expect(detailedResult.modelContent.contains("ada@example.com"))
        #expect(detailedResult.modelContent.contains("Familiar"))
    }

    @Test("Workspace projects immutable context and undo restores only its target")
    func workspaceProjectionAndTargetUndo() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("FamiliarReleaseWorkspace-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FamiliarWorkspaceStore(rootURL: root, quotaBytes: 1_048_576)
        let workspaceID = FamiliarWorkspaceID.project(UUID())
        _ = try store.write(Data("keep".utf8), relativePath: "Outputs/unrelated.txt", in: workspaceID)

        let resourceID = UUID()
        let versionID = UUID()
        let attachmentID = UUID()
        let context = FamiliarToolContext(
            runID: "run",
            toolCallID: "call",
            projectID: UUID(),
            conversationID: UUID(),
            workspaceID: workspaceID,
            resources: [.init(id: resourceID, versionID: versionID, version: 2, displayName: "Notes", filename: "notes.md", mimeType: "text/markdown", contentHash: "resource-hash", extractedText: "project release notes")],
            attachments: [.init(id: attachmentID, kind: .document, filename: "brief.txt", mimeType: "text/plain", relativePath: "Messages/missing/brief.txt", extractedText: "attachment brief", byteSize: 16)]
        )
        let resourcePath = "Files/Resources/\(resourceID.uuidString.lowercased())/notes.md"
        let attachmentPath = "Files/Attachments/\(attachmentID.uuidString.lowercased())/brief.txt"

        let list = try await FamiliarWorkspaceListTool(store: store).execute(.init(), context: context)
        guard case .result(let listResult) = list else { Issue.record("Expected workspace list"); return }
        #expect(listResult.modelContent.contains(resourcePath))
        #expect(listResult.modelContent.contains(attachmentPath))
        #expect(listResult.modelContent.contains("Outputs/unrelated.txt"))

        let read = try await FamiliarWorkspaceReadTool(store: store).execute(.init(path: resourcePath), context: context)
        guard case .result(let readResult) = read else { Issue.record("Expected workspace read"); return }
        #expect(readResult.modelContent.contains("project release notes"))

        let write = try await FamiliarWorkspaceWriteTool(store: store).execute(.init(path: "draft.txt", content: "draft"), context: context)
        guard case .action(let proposal) = write else { Issue.record("Expected workspace write proposal"); return }
        #expect(try !store.contains(relativePath: "Outputs/draft.txt", in: workspaceID))
        let committed = try await proposal.commit()
        #expect(String(decoding: try store.read(relativePath: "Outputs/draft.txt", in: workspaceID), as: UTF8.self) == "draft")
        _ = try store.write(Data("changed after commit".utf8), relativePath: "Outputs/unrelated.txt", in: workspaceID)
        let undo = try #require(committed.undo)
        _ = try await undo()
        #expect(try !store.contains(relativePath: "Outputs/draft.txt", in: workspaceID))
        #expect(String(decoding: try store.read(relativePath: "Outputs/unrelated.txt", in: workspaceID), as: UTF8.self) == "changed after commit")
    }

    @Test("Share preparation produces a top-level share draft payload")
    func shareDraft() async throws {
        let outcome = try await FamiliarPrepareShareTool().execute(.init(title: "Release", text: "Ready"), context: .init())
        guard case .result(let result) = outcome,
              case .shareDraft(let draft) = result.envelope.presentation.content
        else { Issue.record("Expected share draft"); return }
        #expect(draft.title == "Release")
        #expect(draft.text == "Ready")
        #expect(result.envelope.presentation.schemaVersion == 3)
    }
}
