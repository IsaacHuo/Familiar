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

        let service = FamiliarFileImportService(store: FamiliarProjectResourceStore(rootURL: root))
        let resource = try service.importPastedText(
            "  A durable note.  ",
            title: "Field Notes",
            into: project,
            in: context
        )
        let version = try #require(resource.versions.first)

        #expect(resource.displayName == "Field Notes")
        #expect(resource.originRawValue == FamiliarFileOrigin.projectImport.rawValue)
        #expect(version.extractedText == "A durable note.")
        #expect(version.provenanceJSON.contains("user_paste"))
        #expect(version.extractedTextHash == FamiliarHash.sha256("A durable note."))
        #expect(service.quickLookURL(for: version) != nil)
        #expect(throws: FamiliarFileImportError.self) {
            try service.importPastedText(" \n ", into: project, in: context)
        }
        #expect(try context.fetch(FetchDescriptor<FamiliarFileRecord>()).count == 1)
    }

    @Test("Project deletion removes project scope and preserves detached history")
    @MainActor
    func projectDeletionBoundary() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FamiliarWorkspaceDelete-\(UUID().uuidString)", isDirectory: true)
        let resourceStore = FamiliarProjectResourceStore(rootURL: root.appendingPathComponent("Resources"))
        let fileStore = FamiliarFileStore(rootURL: root.appendingPathComponent("Files"))
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
        let grantRecord = FamiliarActivityRecord(activityID: "legacy-grant:fixture", runtimeID: FamiliarGrantArchiveMigration.runtimeID(projectID: project.id),
            assistantTurnID: "legacy-grant", kind: .runtimeNotice, phase: .succeeded, summary: "archived_authorization_provenance",
            detail: "historical audit", sequence: -1, startedAt: Date())
        let rule = FamiliarAuthorizationRuleRecord(
            projectID: project.id,
            capabilityID: "file_write",
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

        _ = try FamiliarFileImportService(store: resourceStore).importPastedText(
            "Delete this resource",
            into: project,
            in: context
        )
        let fileID = UUID()
        let storedFile = try fileStore.write(
            Data("Delete this artifact".utf8),
            projectID: project.id,
            fileID: fileID,
            filename: "artifact.txt"
        )
        context.insert(FamiliarStoredFileVersion(
            id: fileID,
            projectID: project.id,
            identifier: "file_\(fileID.uuidString)",
            title: "File",
            format: .plainText,
            relativePath: storedFile.path,
            byteSize: 20,
            contentHash: storedFile.hash
        ))
        try context.save()

        try FamiliarProjectService(resourceStore: resourceStore, fileStore: fileStore)
            .permanentlyDelete(project, in: context)

        #expect(try context.fetch(FetchDescriptor<FamiliarProject>()).allSatisfy { $0.id == FamiliarProject.dailyProjectID })
        #expect(try context.fetch(FetchDescriptor<FamiliarResource>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<FamiliarStoredFileVersion>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<FamiliarMemoryItem>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<FamiliarMCPBindingRecord>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<FamiliarActivityRecord>()).allSatisfy { $0.activityID != "legacy-grant:fixture" })
        #expect(try context.fetch(FetchDescriptor<FamiliarAuthorizationRuleRecord>()).isEmpty)

        #expect(try context.fetch(FetchDescriptor<FamiliarSkill>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<FamiliarMCPServerRecord>()).count == 1)
        #expect(try #require(context.fetch(FetchDescriptor<FamiliarConversation>()).first).project?.id == FamiliarProject.dailyProjectID)
        #expect(try #require(context.fetch(FetchDescriptor<FamiliarAgentRun>()).first).project == nil)
        #expect(try context.fetch(FetchDescriptor<FamiliarMessage>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<FamiliarAttachment>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<FamiliarContextSnapshotRecord>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<FamiliarEventKitUndoRecord>()).count == 1)
    }

    @Test("Generated document validators reject false files and accept real DOCX and HTML")
    func generatedFileValidation() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let docx = repository.appendingPathComponent("Vendor/AnyDocBridgeRust/tests/fixtures/sample.docx")
        let receipt = try FamiliarFileValidator.validate(fileURL: docx, format: .docx)
        #expect(receipt.format == .docx)
        #expect(receipt.checks.contains("office-package-readable"))

        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "FamiliarFileValidation-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let fake = root.appendingPathComponent("fake.docx")
        try Data("not a document".utf8).write(to: fake)
        #expect(throws: FamiliarFileError.self) {
            _ = try FamiliarFileValidator.validate(fileURL: fake, format: .docx)
        }

        let html = root.appendingPathComponent("report.html")
        try Data("<html><body><h1>Beijing</h1><p>Sources</p></body></html>".utf8).write(to: html)
        let htmlReceipt = try FamiliarFileValidator.validate(
            fileURL: html,
            format: .html,
            requiredText: ["Beijing", "Sources"]
        )
        #expect(htmlReceipt.format == .html)
    }

    @Test("file_publish registers only a validated real output")
    func publishValidatedFile() async throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = repository.appendingPathComponent("Vendor/AnyDocBridgeRust/tests/fixtures/sample.docx")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "FamiliarFilePublish-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = FamiliarWorkspaceStore(rootURL: root.appendingPathComponent("Workspaces"))
        let fileStore = FamiliarFileStore(rootURL: root.appendingPathComponent("Files"))
        let projectID = UUID()
        _ = try workspace.write(
            Data(contentsOf: source),
            relativePath: "Outputs/report.docx",
            in: .project(projectID)
        )
        let tool = FamiliarFilePublishTool(workspaceStore: workspace, fileStore: fileStore)
        let outcome = try await tool.execute(
            .init(path: "Outputs/report.docx", title: "Beijing Report", format: .docx, requiredText: nil),
            context: .init(runID: "run", projectID: projectID, workspaceID: .project(projectID))
        )
        guard case .action(let proposal) = outcome else {
            Issue.record("Expected a reversible publish proposal")
            return
        }
        let committed = try await proposal.commit()
        let descriptor = try #require(committed.result.file)
        #expect(descriptor.format == .docx)
        #expect(descriptor.validationReceipt?.checks.contains("office-package-readable") == true)
        #expect(fileStore.url(relativePath: descriptor.relativePath) != nil)
    }

    @Test("file_read returns the text of a published DOCX so the Agent can verify it")
    func readPublishedFile() async throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = repository.appendingPathComponent("Vendor/AnyDocBridgeRust/tests/fixtures/sample.docx")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "FamiliarFileRead-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = FamiliarWorkspaceStore(rootURL: root.appendingPathComponent("Workspaces"))
        let fileStore = FamiliarFileStore(rootURL: root.appendingPathComponent("Files"))
        let projectID = UUID()
        _ = try workspace.write(
            Data(contentsOf: source),
            relativePath: "Outputs/report.docx",
            in: .project(projectID)
        )
        let publishOutcome = try await FamiliarFilePublishTool(workspaceStore: workspace, fileStore: fileStore)
            .execute(
                .init(path: "Outputs/report.docx", title: "Beijing Report", format: .docx, requiredText: nil),
                context: .init(runID: "run", projectID: projectID, workspaceID: .project(projectID))
            )
        guard case .action(let proposal) = publishOutcome else {
            Issue.record("Expected a reversible publish proposal")
            return
        }
        let descriptor = try #require(try await proposal.commit().result.file)

        let readOutcome = try await FamiliarFileReadTool(store: fileStore).execute(
            .init(identifier: descriptor.identifier),
            context: .init(runID: "run", projectID: projectID, workspaceID: .project(projectID))
        )
        guard case .result(let result) = readOutcome else {
            Issue.record("file_read must be a plain read with no approval")
            return
        }
        // A published DOCX was previously unreadable by the Agent: workspace_read only
        // sees the Workspace copy and rejects non-UTF-8 bytes, so the publish receipt was
        // the only evidence about the delivered file.
        #expect(result.envelope.modelContent.contains("AnyDoc"))
        #expect(result.envelope.modelContent.contains("\"truncated\":false"))
    }

    @Test("Revising a published File adds a version instead of destroying the old one")
    @MainActor
    func fileVersioning() throws {
        let container = try FamiliarTestStore.make()
        let context = container.mainContext
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "FamiliarFileVersions-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let service = FamiliarFileService(store: FamiliarFileStore(rootURL: root))
        let projectID = UUID()

        let firstID = UUID()
        try service.persist(descriptor(id: firstID, projectID: projectID, title: "Beijing", supersedes: nil), in: context)
        let first = try #require(service.storedFile(id: firstID, in: context))
        // A first version is the origin of its own lineage, so it is well-formed on its own.
        #expect(first.version == 1)
        #expect(first.lineageID == firstID)

        let secondID = UUID()
        try service.persist(descriptor(id: secondID, projectID: projectID, title: "Beijing", supersedes: firstID), in: context)
        let second = try #require(service.storedFile(id: secondID, in: context))
        #expect(second.version == 2)
        #expect(second.lineageID == firstID)

        // The previous version must survive: the store keys files by file ID, so each
        // version keeps its own row and its own bytes rather than being overwritten.
        #expect(try context.fetch(FetchDescriptor<FamiliarStoredFileVersion>()).count == 2)
        #expect(service.storedFile(id: firstID, in: context)?.version == 1)
        #expect(service.latestVersion(inLineage: firstID, in: context)?.id == secondID)

        let thirdID = UUID()
        try service.persist(descriptor(id: thirdID, projectID: projectID, title: "Beijing", supersedes: secondID), in: context)
        #expect(service.storedFile(id: thirdID, in: context)?.version == 3)
        #expect(service.storedFile(id: thirdID, in: context)?.lineageID == firstID)

        // Deleting a middle version must not let a later revision reuse its number.
        try service.delete(second, in: context)
        #expect(service.nextVersion(inLineage: firstID, in: context) == 3)
        #expect(service.nextVersion(inLineage: firstID, in: context) == 4)
    }

    private func descriptor(id: UUID, projectID: UUID, title: String, supersedes: UUID?) -> FamiliarFileDescriptor {
        FamiliarFileDescriptor(
            id: id,
            identifier: "file_" + id.uuidString,
            projectID: projectID,
            title: title,
            supersedesFileID: supersedes,
            format: .markdown,
            relativePath: "Projects/\(projectID.uuidString)/Files/\(id.uuidString)/\(title).md",
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
