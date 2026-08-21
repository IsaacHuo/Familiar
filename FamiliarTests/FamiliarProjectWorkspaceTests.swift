import Foundation
import SwiftData
import Testing
@testable import Familiar

@Suite("Familiar project workspace")
struct FamiliarProjectWorkspaceTests {
    @Test("Pasted text becomes a durable project resource and rejects empty input")
    @MainActor
    func pastedTextImport() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FamiliarPastedResource-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let container = try FamiliarTestStore.make()
        let context = container.mainContext
        let project = FamiliarProject(name: "Notes")
        context.insert(project)
        try context.save()

        let service = FamiliarProjectResourceService(store: FamiliarProjectResourceStore(rootURL: root))
        let resource = try service.importPastedText(
            "  A durable note.  ",
            title: "Field Notes",
            into: project,
            in: context
        )
        let version = try #require(resource.versions.first)

        #expect(resource.displayName == "Field Notes")
        #expect(version.source == .importedFile)
        #expect(version.extractedText == "A durable note.")
        #expect(version.extractionEngine == "user_paste")
        #expect(version.extractedTextHash == FamiliarProjectResourceService.sha256("A durable note."))
        #expect(service.quickLookURL(for: version) != nil)
        #expect(throws: FamiliarProjectResourceServiceError.self) {
            try service.importPastedText(" \n ", into: project, in: context)
        }
        #expect(try context.fetch(FetchDescriptor<FamiliarResource>()).count == 1)
    }

    @Test("Project deletion removes project scope and preserves detached history")
    @MainActor
    func projectDeletionBoundary() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FamiliarWorkspaceDelete-\(UUID().uuidString)", isDirectory: true)
        let resourceStore = FamiliarProjectResourceStore(rootURL: root.appendingPathComponent("Resources"))
        let artifactStore = FamiliarArtifactStore(rootURL: root.appendingPathComponent("Artifacts"))
        defer { try? FileManager.default.removeItem(at: root) }

        let container = try FamiliarTestStore.make()
        let context = container.mainContext
        let project = FamiliarProject(name: "Delete Boundary")
        let conversation = FamiliarConversation(title: "History", project: project)
        let message = FamiliarMessage(role: .user, content: "Keep me", sequence: 0, conversation: conversation)
        let attachment = FamiliarAttachment(
            kind: .document,
            filename: "kept.txt",
            mimeType: "text/plain",
            relativePath: "Messages/kept.txt",
            extractedText: "kept",
            byteSize: 4,
            extractionEngine: "fixture",
            extractionVersion: "1",
            detectedFormat: "txt",
            usedOCR: false,
            message: message
        )
        let run = FamiliarAgentRun(
            runtimeID: "historical-run",
            status: .completed,
            conversation: conversation,
            project: project
        )
        let snapshot = FamiliarContextSnapshotRecord(
            createdAt: Date(),
            projectID: project.id,
            projectName: project.name,
            conversationID: conversation.id,
            projectInstruction: nil,
            providerID: "fixture",
            modelID: "fixture",
            exposedToolNamesJSON: "[]",
            maximumInputCharacters: 1_000,
            initialInputCharacters: 10,
            run: run
        )
        let skill = FamiliarSkill(
            stableID: "workspace.fixture",
            version: "1",
            name: "Workspace Fixture",
            descriptionText: "Fixture",
            instructions: "Fixture",
            examplesJSON: "[]",
            allowedToolsJSON: "[]",
            contentHash: "hash"
        )
        let memory = FamiliarMemoryItem(
            scopeRawValue: FamiliarMemoryScope.project.rawValue,
            projectID: project.id,
            conversationID: nil,
            content: "Delete me",
            normalizedKey: "delete me",
            provenance: "fixture",
            confidence: 1,
            createdByRawValue: FamiliarMemoryCreator.user.rawValue
        )
        let server = FamiliarMCPServerRecord(
            displayName: "Fixture",
            endpointString: "https://example.com/mcp",
            serverIdentity: "fixture"
        )
        let mcpBinding = FamiliarMCPBindingRecord(serverID: server.id, projectID: project.id, enabled: true)
        let grant = FamiliarAuthorizationGrant(
            id: UUID(),
            userAction: "confirm",
            source: .builtIn,
            capabilityID: "artifact_write",
            capabilityVersion: "1",
            argumentsHash: "hash",
            projectID: project.id,
            expiresAt: Date().addingTimeInterval(60),
            singleUse: false,
            evidence: "fixture",
            consumedAt: nil,
            state: .issued
        )
        let grantRecord = FamiliarAuthorizationGrantRecord(grant: grant)
        let rule = FamiliarAuthorizationRuleRecord(
            projectID: project.id,
            capabilityID: "artifact_write",
            capabilityVersion: "1",
            targetKey: "target",
            argumentsHash: "hash",
            duration: .always,
            sessionID: nil,
            expiresAt: .distantFuture,
            evidence: "fixture"
        )
        let undo = FamiliarEventKitUndoRecord(
            idempotencyKey: "historical-run:event",
            runtimeID: "historical-run",
            toolCallID: "event",
            toolName: "create_calendar_event",
            kind: .events,
            calendarItemIdentifier: "event-id"
        )

        context.insert(project)
        context.insert(conversation)
        context.insert(message)
        context.insert(attachment)
        context.insert(run)
        context.insert(snapshot)
        context.insert(skill)
        context.insert(memory)
        context.insert(server)
        context.insert(mcpBinding)
        context.insert(grantRecord)
        context.insert(rule)
        context.insert(undo)
        try context.save()

        _ = try FamiliarProjectResourceService(store: resourceStore).importPastedText(
            "Delete this resource",
            into: project,
            in: context
        )
        let artifactID = UUID()
        let storedArtifact = try artifactStore.write(
            Data("Delete this artifact".utf8),
            projectID: project.id,
            artifactID: artifactID,
            filename: "artifact.txt"
        )
        context.insert(FamiliarArtifact(
            id: artifactID,
            projectID: project.id,
            identifier: "artifact_\(artifactID.uuidString)",
            title: "Artifact",
            format: .plainText,
            relativePath: storedArtifact.path,
            byteSize: 20,
            contentHash: storedArtifact.hash
        ))
        try context.save()

        try FamiliarProjectService(resourceStore: resourceStore, artifactStore: artifactStore)
            .permanentlyDelete(project, in: context)

        #expect(try context.fetch(FetchDescriptor<FamiliarProject>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<FamiliarResource>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<FamiliarArtifact>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<FamiliarMemoryItem>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<FamiliarMCPBindingRecord>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<FamiliarAuthorizationGrantRecord>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<FamiliarAuthorizationRuleRecord>()).isEmpty)

        #expect(try context.fetch(FetchDescriptor<FamiliarSkill>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<FamiliarMCPServerRecord>()).count == 1)
        #expect(try #require(context.fetch(FetchDescriptor<FamiliarConversation>()).first).project == nil)
        #expect(try #require(context.fetch(FetchDescriptor<FamiliarAgentRun>()).first).project == nil)
        #expect(try context.fetch(FetchDescriptor<FamiliarMessage>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<FamiliarAttachment>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<FamiliarContextSnapshotRecord>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<FamiliarEventKitUndoRecord>()).count == 1)
    }
}
