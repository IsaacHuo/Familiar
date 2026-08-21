import Foundation
import SwiftData
import Testing
@testable import Familiar

@Suite("Familiar WP5")
struct FamiliarWP5Tests {
    @Test("Artifact store is project scoped, hashes content, and removes atomically")
    func artifactStore() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("FamiliarArtifact-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FamiliarArtifactStore(rootURL: root)
        let projectID = UUID(); let artifactID = UUID()
        let result = try store.write(Data("# body".utf8), projectID: projectID, artifactID: artifactID, filename: "report.md")
        #expect(result.path == "Projects/\(projectID.uuidString)/Artifacts/\(artifactID.uuidString)/report.md")
        #expect(result.hash == FamiliarProjectResourceService.sha256("# body"))
        #expect(try store.read(relativePath: result.path) == Data("# body".utf8))
        #expect(store.url(relativePath: "../outside") == nil)
        try store.remove(projectID: projectID, artifactID: artifactID)
        #expect(store.url(relativePath: result.path) == nil)
    }

    @Test("Artifact write rejects ordinary chat and returns an approved action in a project")
    func artifactWriteScopeAndConfirmation() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("FamiliarArtifactTool-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let tool = FamiliarArtifactWriteTool(store: FamiliarArtifactStore(rootURL: root))
        await #expect(throws: FamiliarArtifactError.self) {
            _ = try await tool.execute(.init(title: "x", content: "body", format: nil), context: .init())
        }
        #expect(!FileManager.default.fileExists(atPath: root.path))
        let outcome = try await tool.execute(.init(title: "x", content: "body", format: .plainText), context: .init(projectID: UUID()))
        guard case .action(let proposal) = outcome else { Issue.record("expected approval action"); return }
        let result = try await proposal.execute()
        #expect(result.artifactIdentifier != nil)
        #expect(result.artifact != nil)
    }

    @Test("Artifact edit preserves the original file for same-session undo")
    func artifactEditAndUndo() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("FamiliarArtifactEdit-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FamiliarArtifactStore(rootURL: root)
        let tool = FamiliarArtifactEditTool(store: store)
        let projectID = UUID()
        let artifactID = UUID()
        let identifier = "artifact_\(artifactID.uuidString)"
        let original = try store.write(Data("original body".utf8), projectID: projectID, artifactID: artifactID, filename: "original.md")

        let outcome = try await tool.execute(
            .init(identifier: identifier, content: "edited body", title: "renamed"),
            context: .init(runID: "run-edit", toolCallID: "call-edit", projectID: projectID)
        )
        guard case .action(let proposal) = outcome else {
            Issue.record("expected approval action")
            return
        }

        let edited = try await proposal.execute()
        let editedArtifact = try #require(edited.artifact)
        #expect(edited.artifactIdentifier == identifier)
        #expect(editedArtifact.title == "renamed")
        #expect(try store.read(relativePath: editedArtifact.relativePath) == Data("edited body".utf8))
        #expect(store.url(relativePath: original.path) == nil)

        let undo = try #require(proposal.undo)
        let restored = try await undo()
        let restoredArtifact = try #require(restored.artifact)
        #expect(restored.artifactIdentifier == identifier)
        #expect(restoredArtifact.title == "original")
        #expect(try store.read(relativePath: restoredArtifact.relativePath) == Data("original body".utf8))
    }

    @Test("Fetched web text imports from the capture without a second fetch")
    @MainActor
    func fetchedWebLineage() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("FamiliarWebCapture-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let project = FamiliarProject(name: "Web")
        let text = "Captured body that is long enough for a resource."
        let capture = FamiliarWebCapture(captureID: "capture-1", urlString: "https://example.com/page", accessedAt: Date(timeIntervalSince1970: 10), contentHash: FamiliarProjectResourceService.sha256(text), text: text, truncated: false, sourceID: "src-1")
        let container = try FamiliarTestStore.make()
        container.mainContext.insert(project)
        let resource = try FamiliarProjectResourceService(store: FamiliarProjectResourceStore(rootURL: root)).importFetchedWebText(capture, into: project, in: container.mainContext)
        let version = try #require(resource.versions.first)
        #expect(version.source == .fetchedWeb)
        #expect(version.sourceURLString == capture.urlString)
        #expect(version.extractedText == text)
        #expect(version.extractedTextHash == capture.contentHash)
    }

}
