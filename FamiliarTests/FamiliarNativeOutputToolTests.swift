import Foundation
import Testing
@testable import Familiar

private struct FamiliarOutputResolverFixture: FamiliarWorkspaceOutputResolving {
    let output: FamiliarResolvedWorkspaceOutput

    func resolveOutput(relativePath: String, workspaceID: FamiliarWorkspaceID) throws -> FamiliarResolvedWorkspaceOutput {
        guard relativePath == output.relativePath else { throw FamiliarWorkspaceError.missingFile }
        return output
    }
}

private actor FamiliarPhotoLibraryFixture: FamiliarPhotoLibrarySaving {
    var status: FamiliarPhotoLibraryAddAuthorization
    var requestCount = 0
    var savedURLs: [URL] = []

    init(status: FamiliarPhotoLibraryAddAuthorization) { self.status = status }

    func addAuthorization() -> FamiliarPhotoLibraryAddAuthorization { status }
    func requestAddAuthorization() -> FamiliarPhotoLibraryAddAuthorization {
        requestCount += 1
        status = .authorized
        return status
    }
    func saveImage(at fileURL: URL) -> String? {
        savedURLs.append(fileURL)
        return "asset-1"
    }
}

@Suite("Native output tools")
struct FamiliarNativeOutputToolTests {
    private func fixture(filename: String = "chart.png") -> FamiliarResolvedWorkspaceOutput {
        .init(
            relativePath: "Outputs/\(filename)",
            filename: filename,
            fileURL: URL(fileURLWithPath: "/tmp/\(filename)"),
            byteSize: 42,
            contentHash: "hash"
        )
    }

    @Test("Photo add-only write does nothing before proposal commit")
    func photoCommitBoundary() async throws {
        let output = fixture()
        let photos = FamiliarPhotoLibraryFixture(status: .notDetermined)
        let tool = FamiliarPhotosSaveOutputTool(resolver: FamiliarOutputResolverFixture(output: output), photos: photos)
        let outcome = try await tool.execute(
            .init(path: output.relativePath),
            context: .init(workspaceID: .conversation(UUID()))
        )
        guard case .action(let proposal) = outcome else { Issue.record("Expected action proposal"); return }
        #expect(await photos.requestCount == 0)
        #expect(await photos.savedURLs.isEmpty)
        #expect(proposal.undoPolicy == .unavailable)

        let committed = try await proposal.commit()
        #expect(await photos.requestCount == 1)
        #expect(await photos.savedURLs == [output.fileURL])
        #expect(committed.undo == nil)
        #expect(committed.result.modelContent.contains("asset-1"))
    }

    @Test("File export returns a typed user-action handoff")
    func fileExportContract() async throws {
        let output = fixture(filename: "report.csv")
        let tool = FamiliarPrepareFileExportTool(resolver: FamiliarOutputResolverFixture(output: output))
        let outcome = try await tool.execute(
            .init(path: output.relativePath),
            context: .init(workspaceID: .project(UUID()))
        )
        guard case .result(let result) = outcome else { Issue.record("Expected result"); return }
        #expect(result.modelContent.contains(output.relativePath))
        #expect(result.modelContent.contains(#""requiresUserAction":true"#))
        #expect(!result.modelContent.contains("/tmp/"))
        guard case .document(let presentation) = result.envelope.presentation.content else {
            Issue.record("Expected document presentation")
            return
        }
        #expect(presentation.url == output.fileURL.absoluteString)
    }

    @Test("Output resolver rejects non-Outputs paths before native access")
    func rejectsNonOutputPath() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("FamiliarNativeOutput-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FamiliarWorkspaceStore(rootURL: root, quotaBytes: 1_024)
        let resolver = FamiliarWorkspaceOutputResolver(store: store)
        #expect(throws: FamiliarNativeOutputToolError.self) {
            _ = try resolver.resolveOutput(relativePath: "Files/private.png", workspaceID: .conversation(UUID()))
        }
    }
}
