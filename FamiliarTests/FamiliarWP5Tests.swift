import Foundation
import SwiftData
import Testing
@testable import Familiar

@Suite("Familiar WP5")
struct FamiliarWP5Tests {
    @Test("File store is project scoped, hashes content, and removes atomically")
    func fileStore() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("FamiliarStoredFileVersion-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FamiliarFileStore(rootURL: root)
        let projectID = UUID(); let fileID = UUID()
        let result = try store.write(Data("# body".utf8), projectID: projectID, fileID: fileID, filename: "report.md")
        #expect(result.path == "Projects/\(projectID.uuidString)/Files/\(fileID.uuidString)/report.md")
        #expect(result.hash == FamiliarHash.sha256("# body"))
        #expect(try store.read(relativePath: result.path) == Data("# body".utf8))
        #expect(store.url(relativePath: "../outside") == nil)
        try store.remove(projectID: projectID, fileID: fileID)
        #expect(store.url(relativePath: result.path) == nil)
    }

    @Test("File write rejects ordinary chat and returns an approved action in a project")
    func fileWriteScopeAndConfirmation() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("FamiliarFileTool-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let tool = FamiliarFileWriteTool(store: FamiliarFileStore(rootURL: root))
        await #expect(throws: FamiliarFileError.self) {
            _ = try await tool.execute(.init(title: "x", content: "body", format: nil), context: .init())
        }
        #expect(!FileManager.default.fileExists(atPath: root.path))
        let outcome = try await tool.execute(.init(title: "x", content: "body", format: .plainText), context: .init(projectID: UUID()))
        guard case .action(let proposal) = outcome else { Issue.record("expected approval action"); return }
        let committed = try await proposal.commit()
        #expect(committed.result.fileIdentifier != nil)
        #expect(committed.result.file != nil)
    }

    @Test("File edit creates a revision and compensation preserves the predecessor")
    func fileEditAndUndo() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("FamiliarFileEdit-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FamiliarFileStore(rootURL: root)
        let tool = FamiliarFileEditTool(store: store)
        let projectID = UUID()
        let fileID = UUID()
        let identifier = "file_\(fileID.uuidString)"
        let original = try store.write(Data("original body".utf8), projectID: projectID, fileID: fileID, filename: "original.md")

        let outcome = try await tool.execute(
            .init(identifier: identifier, content: "edited body", title: "renamed"),
            context: .init(runID: "run-edit", toolCallID: "call-edit", projectID: projectID)
        )
        guard case .action(let proposal) = outcome else {
            Issue.record("expected approval action")
            return
        }

        let committed = try await proposal.commit()
        let editedFile = try #require(committed.result.file)
        #expect(committed.result.fileIdentifier != identifier)
        #expect(editedFile.title == "renamed")
        #expect(try store.read(relativePath: editedFile.relativePath) == Data("edited body".utf8))
        #expect(try store.read(relativePath: original.path) == Data("original body".utf8))

        #expect(editedFile.supersedesFileID == fileID)
        let rollback = try #require(committed.rollback)
        try await rollback()
        #expect(store.url(relativePath: editedFile.relativePath) == nil)
        #expect(try store.read(relativePath: original.path) == Data("original body".utf8))
    }

    @Test("Fetched web text imports from the capture without a second fetch")
    @MainActor
    func fetchedWebLineage() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("FamiliarWebCapture-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let project = FamiliarProject(name: "Web")
        let text = "Captured body that is long enough for a resource."
        let capture = FamiliarWebCapture(captureID: "capture-1", urlString: "https://example.com/page", accessedAt: Date(timeIntervalSince1970: 10), contentHash: FamiliarHash.sha256(text), text: text, truncated: false, sourceID: "src-1")
        let container = try FamiliarTestStore.make()
        container.mainContext.insert(project)
        let resource = try FamiliarFileImportService(store: FamiliarProjectResourceStore(rootURL: root)).importFetchedWebText(capture, into: project, in: container.mainContext)
        let version = try #require(resource.versions.first)
        #expect(resource.originRawValue == FamiliarFileOrigin.webCapture.rawValue)
        #expect(version.sourceURLString == capture.urlString)
        #expect(version.extractedText == capture.resourceText)
        #expect(version.extractedTextHash == FamiliarHash.sha256(capture.resourceText))
        #expect(version.extractedText.contains(capture.contentHash))
    }

}
