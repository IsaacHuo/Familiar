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

    @Test("Generated document validators reject false files and accept real DOCX and HTML")
    func generatedArtifactValidation() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let docx = repository.appendingPathComponent("Vendor/AnyDocBridgeRust/tests/fixtures/sample.docx")
        let receipt = try FamiliarArtifactValidator.validate(fileURL: docx, format: .docx)
        #expect(receipt.format == .docx)
        #expect(receipt.checks.contains("office-package-readable"))

        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "FamiliarArtifactValidation-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let fake = root.appendingPathComponent("fake.docx")
        try Data("not a document".utf8).write(to: fake)
        #expect(throws: FamiliarArtifactError.self) {
            _ = try FamiliarArtifactValidator.validate(fileURL: fake, format: .docx)
        }

        let html = root.appendingPathComponent("report.html")
        try Data("<html><body><h1>Beijing</h1><p>Sources</p></body></html>".utf8).write(to: html)
        let htmlReceipt = try FamiliarArtifactValidator.validate(
            fileURL: html,
            format: .html,
            requiredText: ["Beijing", "Sources"]
        )
        #expect(htmlReceipt.format == .html)
    }

    @Test("artifact_publish registers only a validated real output")
    func publishValidatedArtifact() async throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = repository.appendingPathComponent("Vendor/AnyDocBridgeRust/tests/fixtures/sample.docx")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "FamiliarArtifactPublish-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = FamiliarWorkspaceStore(rootURL: root.appendingPathComponent("Workspaces"))
        let artifactStore = FamiliarArtifactStore(rootURL: root.appendingPathComponent("Artifacts"))
        let projectID = UUID()
        _ = try workspace.write(
            Data(contentsOf: source),
            relativePath: "Outputs/report.docx",
            in: .project(projectID)
        )
        let tool = FamiliarArtifactPublishTool(workspaceStore: workspace, artifactStore: artifactStore)
        let outcome = try await tool.execute(
            .init(path: "Outputs/report.docx", title: "Beijing Report", format: .docx, requiredText: nil),
            context: .init(runID: "run", projectID: projectID, workspaceID: .project(projectID))
        )
        guard case .action(let proposal) = outcome else {
            Issue.record("Expected a reversible publish proposal")
            return
        }
        let committed = try await proposal.commit()
        let descriptor = try #require(committed.result.artifact)
        #expect(descriptor.format == .docx)
        #expect(descriptor.validationReceipt?.checks.contains("office-package-readable") == true)
        #expect(artifactStore.url(relativePath: descriptor.relativePath) != nil)
    }

    @Test("artifact_read returns the text of a published DOCX so the Agent can verify it")
    func readPublishedArtifact() async throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = repository.appendingPathComponent("Vendor/AnyDocBridgeRust/tests/fixtures/sample.docx")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "FamiliarArtifactRead-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = FamiliarWorkspaceStore(rootURL: root.appendingPathComponent("Workspaces"))
        let artifactStore = FamiliarArtifactStore(rootURL: root.appendingPathComponent("Artifacts"))
        let projectID = UUID()
        _ = try workspace.write(
            Data(contentsOf: source),
            relativePath: "Outputs/report.docx",
            in: .project(projectID)
        )
        let publishOutcome = try await FamiliarArtifactPublishTool(workspaceStore: workspace, artifactStore: artifactStore)
            .execute(
                .init(path: "Outputs/report.docx", title: "Beijing Report", format: .docx, requiredText: nil),
                context: .init(runID: "run", projectID: projectID, workspaceID: .project(projectID))
            )
        guard case .action(let proposal) = publishOutcome else {
            Issue.record("Expected a reversible publish proposal")
            return
        }
        let descriptor = try #require(try await proposal.commit().result.artifact)

        let readOutcome = try await FamiliarArtifactReadTool(store: artifactStore).execute(
            .init(identifier: descriptor.identifier),
            context: .init(runID: "run", projectID: projectID, workspaceID: .project(projectID))
        )
        guard case .result(let result) = readOutcome else {
            Issue.record("artifact_read must be a plain read with no approval")
            return
        }
        // A published DOCX was previously unreadable by the Agent: workspace_read only
        // sees the Workspace copy and rejects non-UTF-8 bytes, so the publish receipt was
        // the only evidence about the delivered file.
        #expect(result.envelope.modelContent.contains("AnyDoc"))
        #expect(result.envelope.modelContent.contains("\"truncated\":false"))
    }

    @Test("Revising a published Artifact adds a version instead of destroying the old one")
    @MainActor
    func artifactVersioning() throws {
        let container = try FamiliarTestStore.make()
        let context = container.mainContext
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "FamiliarArtifactVersions-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let service = FamiliarArtifactService(store: FamiliarArtifactStore(rootURL: root))
        let projectID = UUID()

        let firstID = UUID()
        try service.persist(descriptor(id: firstID, projectID: projectID, title: "Beijing", supersedes: nil), in: context)
        let first = try #require(service.storedArtifact(id: firstID, in: context))
        // A first version is the origin of its own lineage, so it is well-formed on its own.
        #expect(first.version == 1)
        #expect(first.lineageID == firstID)

        let secondID = UUID()
        try service.persist(descriptor(id: secondID, projectID: projectID, title: "Beijing", supersedes: firstID), in: context)
        let second = try #require(service.storedArtifact(id: secondID, in: context))
        #expect(second.version == 2)
        #expect(second.lineageID == firstID)

        // The previous version must survive: the store keys files by artifact ID, so each
        // version keeps its own row and its own bytes rather than being overwritten.
        #expect(try context.fetch(FetchDescriptor<FamiliarArtifact>()).count == 2)
        #expect(service.storedArtifact(id: firstID, in: context)?.version == 1)
        #expect(service.latestVersion(inLineage: firstID, in: context)?.id == secondID)

        let thirdID = UUID()
        try service.persist(descriptor(id: thirdID, projectID: projectID, title: "Beijing", supersedes: secondID), in: context)
        #expect(service.storedArtifact(id: thirdID, in: context)?.version == 3)
        #expect(service.storedArtifact(id: thirdID, in: context)?.lineageID == firstID)

        // Deleting a middle version must not let a later revision reuse its number.
        try service.delete(second, in: context)
        #expect(service.nextVersion(inLineage: firstID, in: context) == 4)
    }

    private func descriptor(id: UUID, projectID: UUID, title: String, supersedes: UUID?) -> FamiliarArtifactDescriptor {
        FamiliarArtifactDescriptor(
            id: id,
            identifier: "artifact_" + id.uuidString,
            projectID: projectID,
            title: title,
            supersedesArtifactID: supersedes,
            format: .markdown,
            relativePath: "Projects/\(projectID.uuidString)/Artifacts/\(id.uuidString)/\(title).md",
            byteSize: 12,
            contentHash: String(repeating: "a", count: 64),
            source: .generated,
            sourceURLString: nil,
            sourceResourceID: nil,
            sourceResourceVersionID: nil,
            sourceCaptureID: nil,
            createdByRunID: "run"
        )
    }
}
