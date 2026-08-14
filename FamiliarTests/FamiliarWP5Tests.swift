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

    @Test("V3 store migrates to V4 and starts without artifacts")
    @MainActor
    func v3ToV4() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("FamiliarV3ToV4-\(UUID().uuidString)")
        let url = root.appendingPathComponent(FamiliarModelContainer.storeFilename)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let schema = Schema(versionedSchema: FamiliarSchemaV3.self)
        let config = ModelConfiguration(FamiliarModelContainer.storeName, schema: schema, url: url)
        let old = try ModelContainer(for: schema, configurations: [config])
        old.mainContext.insert(FamiliarSchemaV3.FamiliarProject(name: "old"))
        try old.mainContext.save()
        let current = try FamiliarModelContainer.make(at: url)
        #expect(try current.mainContext.fetch(FetchDescriptor<FamiliarArtifact>()).isEmpty)
        #expect(try current.mainContext.fetch(FetchDescriptor<FamiliarProject>()).count == 1)
    }
}
