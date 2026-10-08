import Foundation
import SwiftUI
import Testing
@testable import Familiar

@Suite("Native and rendered design semantics")
@MainActor
struct FamiliarDesignSystemTests {
    @Test("Rendered content follows native appearance and accessibility text size")
    func rendererAppearanceAndTextSize() throws {
        let light = try decode(FamiliarMarkdownStyle.json(colorScheme: .light, size: .large, contrast: .standard))
        let dark = try decode(FamiliarMarkdownStyle.json(colorScheme: .dark, size: .large, contrast: .standard))
        let accessible = try decode(FamiliarMarkdownStyle.json(colorScheme: .dark, size: .accessibility5, contrast: .increased))
        #expect(light["--familiar-content-duration"] == "150.0ms")
        #expect(light["--familiar-content-offset"] == "2.5px")
        #expect(light["--familiar-ink"] != dark["--familiar-ink"])
        #expect(light["--familiar-inset"] != dark["--familiar-inset"])
        #expect(try pixels(accessible["--familiar-body-size"]) > pixels(light["--familiar-body-size"]))
        #expect(try pixels(accessible["--familiar-caption-size"]) > pixels(light["--familiar-caption-size"]))
        #expect(accessible["--familiar-line-strong"] != nil)
        #expect(accessible.keys.allSatisfy { $0.hasPrefix("--familiar-") })
    }

    @Test("Identical presentation input stays stable without spurious renderer invalidation")
    func stableRendererInput() {
        let first = FamiliarMarkdownStyle.json(colorScheme: .light, size: .large, contrast: .standard)
        let second = FamiliarMarkdownStyle.json(colorScheme: .light, size: .large, contrast: .standard)
        #expect(first == second)
    }

    @Test("File approval exposes a readable filename while exact authorization keeps its identity")
    func readableApprovalTarget() async throws {
        let result = try await FamiliarFileWriteTool(store: .init()).execute(
            .init(title: "Research", content: "# Report", format: .markdown),
            context: .init(runID: "approval", toolCallID: "file", projectID: UUID()))
        guard case .action(let proposal) = result else { Issue.record("Expected file approval"); return }
        #expect(proposal.target == "Research.md")
        #expect(proposal.targetKey.hasPrefix("file_"))
        #expect(proposal.target != proposal.targetKey)
        #expect(proposal.fields.map(\.id) == ["title", "size"])
        #expect(proposal.allowedAuthorizationDurations.first == .once)
    }

    private func decode(_ json: String) throws -> [String: String] {
        try JSONDecoder().decode([String: String].self, from: Data(json.utf8))
    }

    private func pixels(_ value: String?) throws -> Double {
        let value = try #require(value)
        return try #require(Double(value.replacingOccurrences(of: "px", with: "")))
    }
}
