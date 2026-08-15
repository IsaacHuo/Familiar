import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct FamiliarProjectsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FamiliarProject.updatedAt, order: .reverse) private var projects: [FamiliarProject]

    let initialProjectID: UUID?
    let onSelectConversation: (FamiliarConversation) -> Void
    let onNewConversation: (FamiliarProject) -> Void

    @State private var path: [UUID]
    @State private var editor: FamiliarProjectEditorDestination?
    @State private var errorMessage: String?

    init(
        initialProjectID: UUID? = nil,
        onSelectConversation: @escaping (FamiliarConversation) -> Void,
        onNewConversation: @escaping (FamiliarProject) -> Void
    ) {
        self.initialProjectID = initialProjectID
        self.onSelectConversation = onSelectConversation
        self.onNewConversation = onNewConversation
        _path = State(initialValue: initialProjectID.map { [$0] } ?? [])
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                projectSection(
                    title: String(localized: "project.active"),
                    projects: projects.filter { $0.status == .active }
                )
                let archived = projects.filter { $0.status == .archived }
                if !archived.isEmpty {
                    projectSection(title: String(localized: "project.archived"), projects: archived)
                }
            }
            .overlay {
                if projects.isEmpty {
                    ContentUnavailableView(
                        String(localized: "project.empty.title"),
                        systemImage: "folder",
                        description: Text(String(localized: "project.empty.detail"))
                    )
                }
            }
            .navigationTitle(String(localized: "project.all"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.done")) { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        editor = .create
                    } label: {
                        Label(String(localized: "project.create"), systemImage: "plus")
                    }
                    .accessibilityIdentifier("projects.create")
                }
            }
            .navigationDestination(for: UUID.self) { projectID in
                if let project = projects.first(where: { $0.id == projectID }) {
                    FamiliarProjectDetailView(
                        project: project,
                        onSelectConversation: selectConversation,
                        onNewConversation: newConversation,
                        onEdit: { editor = .edit(project) },
                        onError: { errorMessage = $0 }
                    )
                } else {
                    ContentUnavailableView(String(localized: "project.unavailable"), systemImage: "folder.badge.questionmark")
                }
            }
        }
        .sheet(item: $editor) { destination in
            FamiliarProjectEditorView(destination: destination) { project in
                editor = nil
                if path.last != project.id { path.append(project.id) }
            }
        }
        .alert(String(localized: "app.name"), isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button(String(localized: "common.ok"), role: .cancel) {}
        } message: {
            Text(errorMessage ?? String(localized: "error.unknown"))
        }
    }

    private func projectSection(title: String, projects: [FamiliarProject]) -> some View {
        Section(title) {
            ForEach(projects) { project in
                NavigationLink(value: project.id) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(project.name)
                            .font(.body.weight(.medium))
                        if !project.summary.isEmpty {
                            Text(project.summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .padding(.vertical, 3)
                }
            }
        }
    }

    private func selectConversation(_ conversation: FamiliarConversation) {
        dismiss()
        onSelectConversation(conversation)
    }

    private func newConversation(_ project: FamiliarProject) {
        dismiss()
        onNewConversation(project)
    }
}

private struct FamiliarProjectDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let project: FamiliarProject
    let onSelectConversation: (FamiliarConversation) -> Void
    let onNewConversation: (FamiliarProject) -> Void
    let onEdit: () -> Void
    let onError: (String) -> Void

    @State private var showsResourceImporter = false
    @State private var isImportingResource = false
    @State private var previewURL: URL?
    @State private var artifactPreviewURL: URL?
    @State private var resourceToDelete: FamiliarResource?
    @State private var artifactToDelete: FamiliarArtifact?
    @State private var confirmsProjectDeletion = false

    var body: some View {
        List {
            Section {
                if !project.summary.isEmpty {
                    Text(project.summary)
                }
            }

            Section(String(localized: "project.instruction")) {
                Text(project.instruction?.text ?? String(localized: "project.instruction.empty"))
                    .foregroundStyle(project.instruction == nil ? .secondary : .primary)
            }

            Section {
                Button {
                    showsResourceImporter = true
                } label: {
                    if isImportingResource {
                        HStack {
                            ProgressView()
                            Text(String(localized: "resource.importing"))
                        }
                    } else {
                        Label(String(localized: "resource.add"), systemImage: "doc.badge.plus")
                    }
                }
                .disabled(isImportingResource)
                .accessibilityIdentifier("project.addResource")

                ForEach(project.resources.sorted {
                    $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
                }) { resource in
                    if let version = latestVersion(of: resource) {
                        HStack(spacing: 12) {
                            Button {
                                previewURL = FamiliarProjectResourceService().quickLookURL(for: version)
                            } label: {
                                HStack(spacing: 12) {
                                Image(systemName: "doc.text")
                                    .foregroundStyle(FamiliarTheme.accent)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(resource.displayName)
                                        .foregroundStyle(.primary)
                                    Text(resourceDetail(version))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("resource.row.\(resource.id.uuidString)")
                            Button(role: .destructive) {
                                resourceToDelete = resource
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityIdentifier("resource.delete.\(resource.id.uuidString)")
                        }
                    }
                }
            } header: {
                Text(String(localized: "resource.section"))
            } footer: {
                Text(String(localized: "resource.footer"))
            }

            Section(String(localized: "artifact.section", defaultValue: "生成结果")) {
                if projectArtifacts.isEmpty {
                    Text(String(localized: "artifact.empty", defaultValue: "还没有生成结果"))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(projectArtifacts.sorted { $0.updatedAt > $1.updatedAt }) { artifact in
                        HStack(spacing: 12) {
                            Button {
                                artifactPreviewURL = FamiliarArtifactService().exportURL(for: artifact)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: artifact.format == .markdown ? "doc.richtext" : "doc.text")
                                        .foregroundStyle(FamiliarTheme.accent)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(artifact.title).foregroundStyle(.primary)
                                        Text(ByteCountFormatter.string(fromByteCount: artifact.byteSize, countStyle: .file))
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                            Button(role: .destructive) { artifactToDelete = artifact } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }

            Section(String(localized: "project.conversations")) {
                Button {
                    onNewConversation(project)
                } label: {
                    Label(String(localized: "project.new_chat"), systemImage: "square.and.pencil")
                }
                .accessibilityIdentifier("project.newChat")

                if project.conversations.isEmpty {
                    Text(String(localized: "project.conversations.empty"))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(project.conversations.sorted { $0.updatedAt > $1.updatedAt }) { conversation in
                        Button {
                            onSelectConversation(conversation)
                        } label: {
                            HStack {
                                Text(conversation.title)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            }

            Section {
                Button(project.status == .active
                       ? String(localized: "project.archive")
                       : String(localized: "project.unarchive")) {
                    perform {
                        try FamiliarProjectService().setArchived(
                            project.status == .active,
                            for: project,
                            in: modelContext
                        )
                    }
                }

                Button(String(localized: "project.delete"), role: .destructive) {
                    confirmsProjectDeletion = true
                }
                .disabled(project.agentRuns.contains { $0.status == .running })
            } footer: {
                Text(String(localized: "project.delete.footer"))
            }
        }
        .navigationTitle(project.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(String(localized: "common.edit"), action: onEdit)
            }
        }
        .fileImporter(
            isPresented: $showsResourceImporter,
            allowedContentTypes: Self.allowedResourceTypes,
            allowsMultipleSelection: false,
            onCompletion: importResource
        )
        .sheet(isPresented: Binding(
            get: { previewURL != nil },
            set: { if !$0 { previewURL = nil } }
        )) {
            if let previewURL { FamiliarAttachmentQuickLookView(url: previewURL) }
        }
        .sheet(isPresented: Binding(
            get: { artifactPreviewURL != nil },
            set: { if !$0 { artifactPreviewURL = nil } }
        )) {
            if let artifactPreviewURL { FamiliarAttachmentQuickLookView(url: artifactPreviewURL) }
        }
        .confirmationDialog(
            String(localized: "resource.delete.title"),
            isPresented: Binding(
                get: { resourceToDelete != nil },
                set: { if !$0 { resourceToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(String(localized: "common.delete"), role: .destructive) {
                guard let resourceToDelete else { return }
                perform { try FamiliarProjectResourceService().delete(resourceToDelete, in: modelContext) }
                self.resourceToDelete = nil
            }
        } message: {
            Text(String(localized: "resource.delete.detail"))
        }
        .confirmationDialog(
            String(localized: "artifact.delete.title", defaultValue: "删除生成结果"),
            isPresented: Binding(
                get: { artifactToDelete != nil },
                set: { if !$0 { artifactToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(String(localized: "common.delete"), role: .destructive) {
                guard let artifactToDelete else { return }
                perform { try FamiliarArtifactService().delete(artifactToDelete, in: modelContext) }
                self.artifactToDelete = nil
            }
        }
        .confirmationDialog(
            String(localized: "project.delete.confirm.title"),
            isPresented: $confirmsProjectDeletion,
            titleVisibility: .visible
        ) {
            Button(String(localized: "project.delete.confirm"), role: .destructive) {
                perform {
                    try FamiliarProjectService().permanentlyDelete(project, in: modelContext)
                    dismiss()
                }
            }
        } message: {
            Text(String(localized: "project.delete.confirm.detail"))
        }
    }

    private static let allowedResourceTypes: [UTType] = FamiliarAnyDocService.supportedExtensions
        .sorted()
        .compactMap { UTType(filenameExtension: $0) }
        .isEmpty ? [.data] : FamiliarAnyDocService.supportedExtensions.sorted().compactMap { UTType(filenameExtension: $0) }

    private func latestVersion(of resource: FamiliarResource) -> FamiliarResourceVersion? {
        resource.versions.max {
            $0.version == $1.version ? $0.createdAt < $1.createdAt : $0.version < $1.version
        }
    }

    private var projectArtifacts: [FamiliarArtifact] {
        let projectID = project.id
        return (try? modelContext.fetch(FetchDescriptor<FamiliarArtifact>(
            predicate: #Predicate { $0.projectID == projectID }
        ))) ?? []
    }

    private func resourceDetail(_ version: FamiliarResourceVersion) -> String {
        var values = [version.detectedFormat.uppercased(), ByteCountFormatter.string(fromByteCount: version.byteSize, countStyle: .file)]
        if version.usedOCR { values.append(String(localized: "resource.ocr")) }
        return values.joined(separator: " · ")
    }

    private func importResource(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            isImportingResource = true
            Task {
                defer { isImportingResource = false }
                do {
                    try await FamiliarProjectResourceService().importDocument(from: url, into: project, in: modelContext)
                } catch {
                    onError(error.localizedDescription)
                }
            }
        } catch {
            onError(error.localizedDescription)
        }
    }

    private func perform(_ operation: () throws -> Void) {
        do {
            try operation()
        } catch {
            onError(error.localizedDescription)
        }
    }
}

private enum FamiliarProjectEditorDestination: Identifiable {
    case create
    case edit(FamiliarProject)

    var id: String {
        switch self {
        case .create: "create"
        case .edit(let project): "edit-\(project.id.uuidString)"
        }
    }
}

private struct FamiliarProjectEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let destination: FamiliarProjectEditorDestination
    let onSave: (FamiliarProject) -> Void

    @State private var name: String
    @State private var summary: String
    @State private var instruction: String
    @State private var errorMessage: String?

    init(destination: FamiliarProjectEditorDestination, onSave: @escaping (FamiliarProject) -> Void) {
        self.destination = destination
        self.onSave = onSave
        switch destination {
        case .create:
            _name = State(initialValue: "")
            _summary = State(initialValue: "")
            _instruction = State(initialValue: "")
        case .edit(let project):
            _name = State(initialValue: project.name)
            _summary = State(initialValue: project.summary)
            _instruction = State(initialValue: project.instruction?.text ?? "")
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "project.details")) {
                    TextField(String(localized: "project.name"), text: $name)
                        .textInputAutocapitalization(.sentences)
                    TextField(String(localized: "project.summary"), text: $summary, axis: .vertical)
                        .lineLimit(2...6)
                }
                Section(String(localized: "project.instruction")) {
                    TextEditor(text: $instruction)
                        .frame(minHeight: 160)
                    Text("\(min(instruction.count, FamiliarProjectService.maximumInstructionLength)) / \(FamiliarProjectService.maximumInstructionLength)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(destination.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "common.save"), action: save)
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("project.editor.save")
                }
            }
        }
        .alert(String(localized: "app.name"), isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button(String(localized: "common.ok"), role: .cancel) {}
        } message: {
            Text(errorMessage ?? String(localized: "error.unknown"))
        }
        .onChange(of: name) { _, value in
            if value.count > FamiliarProjectService.maximumNameLength {
                name = String(value.prefix(FamiliarProjectService.maximumNameLength))
            }
        }
        .onChange(of: summary) { _, value in
            if value.count > FamiliarProjectService.maximumSummaryLength {
                summary = String(value.prefix(FamiliarProjectService.maximumSummaryLength))
            }
        }
        .onChange(of: instruction) { _, value in
            if value.count > FamiliarProjectService.maximumInstructionLength {
                instruction = String(value.prefix(FamiliarProjectService.maximumInstructionLength))
            }
        }
    }

    private func save() {
        let service = FamiliarProjectService()
        do {
            let project: FamiliarProject
            switch destination {
            case .create:
                project = try service.create(name: name, summary: summary, in: modelContext)
            case .edit(let existing):
                try service.update(existing, name: name, summary: summary, in: modelContext)
                project = existing
            }
            try service.updateInstruction(project, text: instruction, in: modelContext)
            onSave(project)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private extension FamiliarProjectEditorDestination {
    var title: String {
        switch self {
        case .create: String(localized: "project.create")
        case .edit: String(localized: "project.edit")
        }
    }
}
