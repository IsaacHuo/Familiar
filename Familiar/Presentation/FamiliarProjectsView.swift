import SwiftData
import SwiftUI
import UniformTypeIdentifiers

enum FamiliarProjectConversationRequest: Equatable, Sendable {
    case open(conversationID: UUID)
    case create(projectID: UUID)
}

struct FamiliarProjectsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FamiliarProject.updatedAt, order: .reverse) private var projects: [FamiliarProject]

    let initialProjectID: UUID?
    private let registry: FamiliarToolRegistry?
    private let onConversationRequest: ((FamiliarProjectConversationRequest) -> Void)?
    private let onSelectConversation: ((FamiliarConversation) -> Void)?
    private let onNewConversation: ((FamiliarProject) -> Void)?
    private let onDeleteConversations: (([FamiliarConversation]) -> Void)?

    @State private var path: [UUID]
    @State private var editor: FamiliarProjectEditorDestination?
    @State private var errorMessage: String?

    init(
        initialProjectID: UUID? = nil,
        registry: FamiliarToolRegistry? = nil,
        onConversationRequest: @escaping (FamiliarProjectConversationRequest) -> Void,
        onDeleteConversations: @escaping ([FamiliarConversation]) -> Void
    ) {
        self.initialProjectID = initialProjectID
        self.registry = registry
        self.onConversationRequest = onConversationRequest
        self.onDeleteConversations = onDeleteConversations
        onSelectConversation = nil
        onNewConversation = nil
        _path = State(initialValue: initialProjectID.map { [$0] } ?? [])
    }

    init(
        initialProjectID: UUID? = nil,
        registry: FamiliarToolRegistry? = nil,
        onSelectConversation: @escaping (FamiliarConversation) -> Void,
        onNewConversation: @escaping (FamiliarProject) -> Void
    ) {
        self.initialProjectID = initialProjectID
        self.registry = registry
        onConversationRequest = nil
        onDeleteConversations = nil
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
                        registry: registry,
                        onConversationRequest: handleConversationRequest,
                        onDeleteConversations: onDeleteConversations,
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
                    VStack(alignment: .leading, spacing: FamiliarSpacing.xSmall) {
                        Text(project.name)
                            .font(FamiliarTypography.body.weight(.medium))
                        if !project.summary.isEmpty {
                            Text(project.summary)
                                .font(FamiliarTypography.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .padding(.vertical, FamiliarSpacing.xSmall)
                }
            }
        }
    }

    private func handleConversationRequest(_ request: FamiliarProjectConversationRequest) {
        dismiss()
        if let onConversationRequest {
            onConversationRequest(request)
            return
        }
        switch request {
        case .open(let conversationID):
            guard let conversation = projects.lazy.flatMap(\.conversations).first(where: { $0.id == conversationID }) else { return }
            onSelectConversation?(conversation)
        case .create(let projectID):
            guard let project = projects.first(where: { $0.id == projectID }) else { return }
            onNewConversation?(project)
        }
    }
}

private struct FamiliarProjectDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \FamiliarArtifact.updatedAt, order: .reverse) private var allArtifacts: [FamiliarArtifact]

    let project: FamiliarProject
    let registry: FamiliarToolRegistry?
    let onConversationRequest: (FamiliarProjectConversationRequest) -> Void
    let onDeleteConversations: (([FamiliarConversation]) -> Void)?
    let onEdit: () -> Void
    let onError: (String) -> Void

    @State private var showsResourceImporter = false
    @State private var resourceEntry: FamiliarProjectResourceEntryDestination?
    @State private var isImportingResource = false
    @State private var previewDocument: FamiliarProjectPreviewDocument?
    @State private var resourceToDelete: FamiliarResource?
    @State private var artifactToDelete: FamiliarArtifact?
    @State private var confirmsProjectDeletion = false

    var body: some View {
        List {
            Section {
                FamiliarProjectHero(project: project)
                projectActions
            }

            Section {
                if recentResources.isEmpty {
                    emptyRow(
                        String(localized: "resource.empty", defaultValue: "No resources yet"),
                        systemImage: "doc"
                    )
                } else {
                    ForEach(recentResources) { resource in
                        resourceRow(resource)
                    }
                }
                resourceImportMenu
            } header: {
                FamiliarProjectSectionHeader(
                    title: String(localized: "resource.section"),
                    count: project.resources.count
                ) {
                    FamiliarProjectResourcesView(
                        resources: sortedResources,
                        onPreview: previewResource,
                        onDelete: { resourceToDelete = $0 },
                        onDeleteAll: {
                            perform { try FamiliarProjectResourceService().deleteAll(from: project, in: modelContext) }
                        }
                    )
                }
            } footer: {
                if isImportingResource {
                    Label(String(localized: "resource.importing"), systemImage: "arrow.down.doc")
                } else {
                    Text(String(localized: "resource.footer"))
                }
            }

            Section {
                if recentArtifacts.isEmpty {
                    emptyRow(
                        String(localized: "artifact.empty", defaultValue: "No artifacts yet"),
                        systemImage: "doc.badge.gearshape"
                    )
                } else {
                    ForEach(recentArtifacts) { artifact in
                        artifactRow(artifact)
                    }
                }
            } header: {
                FamiliarProjectSectionHeader(
                    title: String(localized: "artifact.section", defaultValue: "Artifacts"),
                    count: projectArtifacts.count,
                    destination: {
                        FamiliarProjectArtifactsView(
                            artifacts: projectArtifacts,
                            onPreview: previewArtifact,
                            onDelete: { artifactToDelete = $0 }
                        )
                    }
                )
            }

            Section(String(localized: "project.context", defaultValue: "Project Context")) {
                NavigationLink {
                    FamiliarProjectEnvironmentView(projectID: project.id)
                } label: {
                    FamiliarProjectContextRow(
                        title: String(localized: "project.environment", defaultValue: "Environment"),
                        detail: String(localized: "project.environment.detail", defaultValue: "Isolated Linux dependencies and verified lock"),
                        symbol: "shippingbox",
                        count: nil
                    )
                }

                NavigationLink {
                    FamiliarProjectSkillsView(projectID: project.id)
                } label: {
                    FamiliarProjectContextRow(
                        title: String(localized: "settings.skills", defaultValue: "Skills"),
                        detail: String(localized: "project.skills.context_detail", defaultValue: "Instruction-only Skills available for on-demand loading"),
                        symbol: "wand.and.stars",
                        count: nil
                    )
                }

                if let registry {
                    NavigationLink {
                        FamiliarProjectCapabilitiesView(projectID: project.id, registry: registry)
                    } label: {
                        FamiliarProjectContextRow(
                            title: String(localized: "project.capabilities", defaultValue: "Capabilities"),
                            detail: String(localized: "project.capabilities.detail", defaultValue: "Tools this Project may expose to the Agent"),
                            symbol: "switch.2",
                            count: nil
                        )
                    }
                }

                NavigationLink {
                    FamiliarProjectConversationsView(
                        conversations: sortedConversations,
                        onSelect: { onConversationRequest(.open(conversationID: $0.id)) },
                        onDeleteAll: deleteAllConversations
                    )
                } label: {
                    FamiliarProjectContextRow(
                        title: String(localized: "project.conversations"),
                        detail: String(
                            localized: "project.conversations.context_detail",
                            defaultValue: "Chats that share this project context"
                        ),
                        symbol: "bubble.left.and.bubble.right",
                        count: sortedConversations.count
                    )
                }

                NavigationLink {
                    FamiliarProjectRunsView(runs: sortedRuns)
                } label: {
                    FamiliarProjectContextRow(
                        title: String(localized: "project.runs", defaultValue: "Runs"),
                        detail: String(
                            localized: "project.runs.context_detail",
                            defaultValue: "Execution history and frozen context"
                        ),
                        symbol: "bolt",
                        count: sortedRuns.count
                    )
                }
            }
        }
        .navigationTitle(project.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        onConversationRequest(.create(projectID: project.id))
                    } label: {
                        Label(String(localized: "project.new_chat"), systemImage: "square.and.pencil")
                    }
                    Divider()
                    Button(action: onEdit) {
                        Label(String(localized: "common.edit"), systemImage: "pencil")
                    }
                    Button {
                        perform {
                            try FamiliarProjectService().setArchived(
                                project.status == .active,
                                for: project,
                                in: modelContext
                            )
                        }
                    } label: {
                        Label(
                            project.status == .active
                                ? String(localized: "project.archive")
                                : String(localized: "project.unarchive"),
                            systemImage: project.status == .active ? "archivebox" : "arrow.uturn.backward"
                        )
                    }
                    Button(role: .destructive) {
                        confirmsProjectDeletion = true
                    } label: {
                        Label(String(localized: "project.delete"), systemImage: "trash")
                    }
                    .disabled(project.agentRuns.contains { $0.status == .running })
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel(String(localized: "project.actions", defaultValue: "Project Actions"))
            }
        }
        .fileImporter(
            isPresented: $showsResourceImporter,
            allowedContentTypes: Self.allowedResourceTypes,
            allowsMultipleSelection: false,
            onCompletion: importResource
        )
        .sheet(item: $resourceEntry) { destination in
            FamiliarProjectResourceEntryView(destination: destination) { title, value in
                resourceEntry = nil
                importEnteredResource(destination, title: title, value: value)
            }
        }
        .sheet(item: $previewDocument) { document in
            FamiliarAttachmentPreviewView(url: document.url, format: document.format)
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
            String(localized: "artifact.delete.title", defaultValue: "Delete this artifact?"),
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

    private var projectActions: some View {
        Group {
            if !sortedConversations.isEmpty {
                primaryProjectAction
            }
        }
    }

    private var primaryProjectAction: some View {
        Button {
            if let conversation = sortedConversations.first {
                onConversationRequest(.open(conversationID: conversation.id))
            } else {
                onConversationRequest(.create(projectID: project.id))
            }
        } label: {
            Label(
                String(localized: "project.continue_chat", defaultValue: "Continue Chat"),
                systemImage: "bubble.left.and.bubble.right"
            )
            .frame(maxWidth: .infinity, minHeight: FamiliarControlSize.minimumHitTarget)
        }
        .buttonStyle(FamiliarPillButtonStyle(prominence: .primary))
        .accessibilityIdentifier("project.continueChat")
    }

    private var resourceImportMenu: some View {
        Menu {
            Button {
                showsResourceImporter = true
            } label: {
                Label(String(localized: "resource.add"), systemImage: "doc.badge.plus")
            }
            Button {
                resourceEntry = .webPage
            } label: {
                Label(String(localized: "resource.add_web", defaultValue: "Add Web Page"), systemImage: "link")
            }
            Button {
                resourceEntry = .pastedText
            } label: {
                Label(String(localized: "resource.add_text", defaultValue: "Paste Text"), systemImage: "text.quote")
            }
        } label: {
            if isImportingResource {
                Label {
                    Text(String(localized: "resource.importing"))
                } icon: {
                    ProgressView()
                }
            } else {
                Label(String(localized: "resource.add"), systemImage: "plus")
            }
        }
        .font(FamiliarTypography.button)
        .foregroundStyle(FamiliarTheme.accent)
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
        .disabled(isImportingResource)
        .accessibilityLabel(String(localized: "resource.add"))
        .accessibilityIdentifier("project.addResource")
    }

    private var projectArtifacts: [FamiliarArtifact] {
        allArtifacts.filter { $0.projectID == project.id }
    }
    private var deleteAllConversations: (() -> Void)? {
        guard let onDeleteConversations else { return nil }
        let project = project
        return { onDeleteConversations(project.conversations) }
    }

    private var sortedResources: [FamiliarResource] { project.resources.sorted { $0.updatedAt > $1.updatedAt } }
    private var sortedConversations: [FamiliarConversation] { project.conversations.sorted { $0.updatedAt > $1.updatedAt } }
    private var sortedRuns: [FamiliarAgentRun] { project.agentRuns.sorted { $0.startedAt > $1.startedAt } }
    private var recentResources: [FamiliarResource] { Array(sortedResources.prefix(3)) }
    /// One entry per deliverable: taking the first three rows flatly would show v3, v2
    /// and v1 of the same file as three separate recent artifacts.
    private var recentArtifacts: [FamiliarArtifact] {
        let latestPerLineage = Dictionary(grouping: projectArtifacts, by: \.lineageID)
            .compactMap { $0.value.max { $0.version < $1.version } }
            .sorted { lhs, rhs in
                if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
                return lhs.id.uuidString < rhs.id.uuidString
            }
        return Array(latestPerLineage.prefix(3))
    }

    private func resourceRow(_ resource: FamiliarResource) -> some View {
        FamiliarProjectResourceRow(
            resource: resource,
            onPreview: { previewResource(resource) },
            onDelete: { resourceToDelete = resource }
        )
    }

    private func artifactRow(_ artifact: FamiliarArtifact) -> some View {
        FamiliarProjectArtifactRow(
            artifact: artifact,
            versionCount: projectArtifacts.count { $0.lineageID == artifact.lineageID },
            exportURL: FamiliarArtifactService().exportURL(for: artifact),
            onPreview: { previewArtifact(artifact) },
            onDelete: { artifactToDelete = artifact }
        )
    }

    private func previewResource(_ resource: FamiliarResource) {
        guard let version = FamiliarProjectResourceService.latestVersion(of: resource),
              let url = FamiliarProjectResourceService().quickLookURL(for: version)
        else { return }
        previewDocument = FamiliarProjectPreviewDocument(url: url, format: nil)
    }

    private func previewArtifact(_ artifact: FamiliarArtifact) {
        guard let url = FamiliarArtifactService().exportURL(for: artifact) else { return }
        previewDocument = FamiliarProjectPreviewDocument(url: url, format: artifact.format)
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

    private func importEnteredResource(
        _ destination: FamiliarProjectResourceEntryDestination,
        title: String,
        value: String
    ) {
        isImportingResource = true
        Task {
            defer { isImportingResource = false }
            do {
                switch destination {
                case .webPage:
                    try await FamiliarProjectResourceService().importWebPage(
                        from: value,
                        into: project,
                        in: modelContext
                    )
                case .pastedText:
                    try FamiliarProjectResourceService().importPastedText(
                        value,
                        title: title,
                        into: project,
                        in: modelContext
                    )
                }
            } catch {
                onError(error.localizedDescription)
            }
        }
    }

    private func emptyRow(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .foregroundStyle(.secondary)
    }

    private static let allowedResourceTypes: [UTType] = FamiliarAnyDocService.supportedExtensions
        .sorted()
        .compactMap { UTType(filenameExtension: $0) }
        .isEmpty ? [.data] : FamiliarAnyDocService.supportedExtensions.sorted().compactMap { UTType(filenameExtension: $0) }

    private func perform(_ operation: () throws -> Void) {
        do {
            try operation()
        } catch {
            onError(error.localizedDescription)
        }
    }

}

private struct FamiliarProjectEnvironmentView: View {
    @Query(sort: \FamiliarProjectEnvironmentRecord.preparedAt, order: .reverse)
    private var records: [FamiliarProjectEnvironmentRecord]
    let projectID: UUID

    var body: some View {
        List {
            if let record = records.first(where: { $0.projectID == projectID }) {
                Section(String(localized: "project.environment", defaultValue: "Environment")) {
                    LabeledContent(String(localized: "environment.state", defaultValue: "State"), value: record.state.rawValue)
                    LabeledContent(String(localized: "environment.python", defaultValue: "Python"), value: record.pythonVersion)
                    LabeledContent(String(localized: "environment.revision", defaultValue: "Revision"), value: record.revision.uuidString)
                    LabeledContent(String(localized: "environment.size", defaultValue: "Size"), value: ByteCountFormatter.string(fromByteCount: record.byteSize, countStyle: .file))
                    LabeledContent(String(localized: "environment.lock", defaultValue: "Lock"), value: String(record.lockHash.prefix(16)))
                }
                Section(String(localized: "environment.packages", defaultValue: "Resolved Packages")) {
                    ForEach(decodedPackages(record), id: \.self) { package in
                        Text(package).font(.body.monospaced())
                    }
                }
            } else {
                ContentUnavailableView(
                    String(localized: "environment.not_prepared", defaultValue: "Environment not prepared"),
                    systemImage: "shippingbox",
                    description: Text(String(localized: "environment.not_prepared.detail", defaultValue: "The Agent can propose dependencies with environment_prepare from a Project Chat."))
                )
            }
        }
        .navigationTitle(String(localized: "project.environment", defaultValue: "Environment"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func decodedPackages(_ record: FamiliarProjectEnvironmentRecord) -> [String] {
        guard let data = record.resolvedPackagesJSON.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }
}

private struct FamiliarProjectSkillsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FamiliarSkill.name) private var skills: [FamiliarSkill]
    @Query private var allBindings: [FamiliarProjectSkillBindingRecord]
    let projectID: UUID

    var body: some View {
        List {
            if skills.isEmpty {
                ContentUnavailableView(String(localized: "settings.skills.empty", defaultValue: "No installed skills"), systemImage: "wand.and.stars")
            }
            ForEach(skills) { skill in
                Toggle(isOn: Binding(
                    get: { isEnabled(skill.id) },
                    set: { enabled in
                        try? FamiliarProjectService().setSkill(skill.id, enabled: enabled, projectID: projectID, in: modelContext)
                    }
                )) {
                    VStack(alignment: .leading, spacing: FamiliarSpacing.xSmall) {
                        Text(skill.name)
                        Text(skill.descriptionText).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle(String(localized: "settings.skills", defaultValue: "Skills"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func isEnabled(_ skillID: UUID) -> Bool {
        allBindings.first { $0.projectID == projectID && $0.skillID == skillID }?.enabled == true
    }
}

private struct FamiliarProjectCapabilitiesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allBindings: [FamiliarProjectCapabilityBindingRecord]
    let projectID: UUID
    let registry: FamiliarToolRegistry
    @State private var manifests: [FamiliarToolManifest] = []

    var body: some View {
        List(manifests, id: \.id) { manifest in
            Toggle(isOn: Binding(
                get: { isEnabled(manifest.id) },
                set: { enabled in
                    try? FamiliarProjectService().setCapability(
                        manifest.id,
                        enabled: enabled,
                        allCapabilityIDs: manifests.map(\.id),
                        projectID: projectID,
                        in: modelContext
                    )
                }
            )) {
                VStack(alignment: .leading, spacing: FamiliarSpacing.xSmall) {
                    Text(manifest.title)
                    Text(manifest.description).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            .disabled(coreCapabilities.contains(manifest.name))
        }
        .navigationTitle(String(localized: "project.capabilities", defaultValue: "Capabilities"))
        .navigationBarTitleDisplayMode(.inline)
        .task { manifests = await registry.manifests() }
    }

    private let coreCapabilities: Set<String> = ["task_plan", "ask_user", "skill_list", "skill_read", "environment_status"]

    private func isEnabled(_ id: String) -> Bool {
        let projectBindings = allBindings.filter { $0.projectID == projectID }
        guard !projectBindings.isEmpty else { return true }
        return projectBindings.first { $0.capabilityID == id }?.enabled == true
    }
}

private struct FamiliarProjectHero: View {
    let project: FamiliarProject

    var body: some View {
        VStack(alignment: .leading, spacing: FamiliarSpacing.medium) {
            if !project.summary.isEmpty {
                Text(project.summary)
                    .font(FamiliarTypography.body)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: FamiliarSpacing.xSmall) {
                Label(String(localized: "project.instruction"), systemImage: "text.quote")
                    .font(FamiliarTypography.caption.weight(.semibold))
                    .foregroundStyle(FamiliarTheme.accent)
                Text(project.instruction?.text ?? String(localized: "project.instruction.empty"))
                    .font(FamiliarTypography.secondary)
                    .foregroundStyle(project.instruction == nil ? .secondary : .primary)
                    .lineLimit(4)
            }
        }
        .padding(.vertical, FamiliarSpacing.small)
        .accessibilityElement(children: .combine)
    }
}

private struct FamiliarProjectContextRow: View {
    let title: String
    let detail: String
    let symbol: String
    let count: Int?

    var body: some View {
        HStack(spacing: FamiliarSpacing.medium) {
            Image(systemName: symbol)
                .font(.system(size: FamiliarIconSize.standard, weight: .medium))
                .foregroundStyle(FamiliarTheme.accent)
                .frame(width: FamiliarControlSize.compactVisual)

            VStack(alignment: .leading, spacing: FamiliarSpacing.xSmall) {
                Text(title)
                    .font(FamiliarTypography.body)
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(FamiliarTypography.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: FamiliarSpacing.small)

            if let count {
                Text("\(count)")
                    .font(FamiliarTypography.metadata)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, FamiliarSpacing.xSmall)
    }
}

private struct FamiliarProjectSectionHeader<Destination: View>: View {
    let title: String
    let count: Int
    @ViewBuilder let destination: Destination

    init(
        title: String,
        count: Int,
        @ViewBuilder destination: () -> Destination
    ) {
        self.title = title
        self.count = count
        self.destination = destination()
    }

    var body: some View {
        HStack(spacing: FamiliarSpacing.small) {
            Text(title)
                .font(FamiliarTypography.sectionTitle)
            Text("\(count)")
                .font(FamiliarTypography.metadata)
                .foregroundStyle(.tertiary)
            Spacer()
            NavigationLink {
                destination
            } label: {
                Text(String(localized: "common.view_all", defaultValue: "View All"))
                    .font(FamiliarTypography.caption.weight(.medium))
            }
            .disabled(count == 0)
        }
    }
}

private struct FamiliarProjectResourcesView: View {
    let resources: [FamiliarResource]
    let onPreview: (FamiliarResource) -> Void
    let onDelete: (FamiliarResource) -> Void
    let onDeleteAll: () -> Void

    @State private var confirmsDeleteAll = false

    var body: some View {
        List(resources) { resource in
            FamiliarProjectResourceRow(
                resource: resource,
                onPreview: { onPreview(resource) },
                onDelete: { onDelete(resource) }
            )
        }
        .navigationTitle(String(localized: "resource.section"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    confirmsDeleteAll = true
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(resources.isEmpty)
                .accessibilityLabel(String(localized: "resource.delete_all", defaultValue: "Delete All Resources"))
                .accessibilityIdentifier("resource.deleteAll")
            }
        }
        .confirmationDialog(
            String(localized: "resource.delete_all.title", defaultValue: "Delete all resources?"),
            isPresented: $confirmsDeleteAll,
            titleVisibility: .visible
        ) {
            Button(String(localized: "common.delete_all", defaultValue: "Delete All"), role: .destructive) {
                onDeleteAll()
            }
            Button(String(localized: "common.cancel"), role: .cancel) {}
        } message: {
            Text(String(
                localized: "resource.delete_all.detail",
                defaultValue: "Every document in this project, including all of their versions, will be removed."
            ))
        }
    }
}

private struct FamiliarProjectResourceRow: View {
    let resource: FamiliarResource
    let onPreview: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: FamiliarSpacing.medium) {
            Button(action: onPreview) {
                HStack(spacing: FamiliarSpacing.medium) {
                    Image(systemName: latestVersion?.source == .fetchedWeb ? "link" : "doc.text")
                        .foregroundStyle(FamiliarTheme.accent)
                    VStack(alignment: .leading, spacing: FamiliarSpacing.xSmall) {
                        Text(resource.displayName)
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                        if let latestVersion {
                            Text(resourceDetail(latestVersion))
                                .font(FamiliarTypography.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("resource.row.\(resource.id.uuidString)")
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
                    .frame(
                        minWidth: FamiliarControlSize.minimumHitTarget,
                        minHeight: FamiliarControlSize.minimumHitTarget
                    )
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("resource.delete.\(resource.id.uuidString)")
        }
    }

    private var latestVersion: FamiliarResourceVersion? {
        FamiliarProjectResourceService.latestVersion(of: resource)
    }

    private func resourceDetail(_ version: FamiliarResourceVersion) -> String {
        var values = [
            version.detectedFormat.uppercased(),
            ByteCountFormatter.string(fromByteCount: version.byteSize, countStyle: .file),
            "v\(version.version)"
        ]
        if version.usedOCR { values.append(String(localized: "resource.ocr")) }
        return values.joined(separator: " · ")
    }
}

private struct FamiliarProjectArtifactsView: View {
    let artifacts: [FamiliarArtifact]
    let onPreview: (FamiliarArtifact) -> Void
    let onDelete: (FamiliarArtifact) -> Void

    /// Newest version first, with the rest kept as history. Identifiable by lineage so
    /// the list needs no force unwrap of a possibly-empty group.
    private struct Lineage: Identifiable {
        let id: UUID
        let latest: FamiliarArtifact
        let earlier: [FamiliarArtifact]
    }

    /// Grouped by lineage so one deliverable is one row. Listing every version flatly
    /// would present successive revisions of the same file as unrelated Artifacts.
    private var lineages: [Lineage] {
        Dictionary(grouping: artifacts, by: \.lineageID)
            .compactMap { lineageID, group -> Lineage? in
                let ordered = group.sorted { $0.version > $1.version }
                guard let latest = ordered.first else { return nil }
                return Lineage(id: lineageID, latest: latest, earlier: Array(ordered.dropFirst()))
            }
            .sorted { lhs, rhs in
                if lhs.latest.updatedAt != rhs.latest.updatedAt {
                    return lhs.latest.updatedAt > rhs.latest.updatedAt
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    var body: some View {
        List(lineages) { lineage in
            FamiliarProjectArtifactRow(
                artifact: lineage.latest,
                versionCount: lineage.earlier.count + 1,
                exportURL: FamiliarArtifactService().exportURL(for: lineage.latest),
                onPreview: { onPreview(lineage.latest) },
                onDelete: { onDelete(lineage.latest) }
            )
            if !lineage.earlier.isEmpty {
                NavigationLink {
                    FamiliarArtifactVersionHistoryView(
                        title: lineage.latest.title,
                        versions: lineage.earlier,
                        onPreview: onPreview,
                        onDelete: onDelete
                    )
                } label: {
                    Label(
                        String(format: String(localized: "artifact.versions.count", defaultValue: "%@ earlier versions"), NSNumber(value: lineage.earlier.count)),
                        systemImage: "clock.arrow.circlepath"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(String(localized: "artifact.section", defaultValue: "Artifacts"))
    }
}

/// Superseded versions of one deliverable. They remain previewable and shareable
/// because each version keeps its own row and its own bytes on disk.
private struct FamiliarArtifactVersionHistoryView: View {
    let title: String
    let versions: [FamiliarArtifact]
    let onPreview: (FamiliarArtifact) -> Void
    let onDelete: (FamiliarArtifact) -> Void

    var body: some View {
        List(versions) { version in
            FamiliarProjectArtifactRow(
                artifact: version,
                versionCount: versions.count + 1,
                exportURL: FamiliarArtifactService().exportURL(for: version),
                onPreview: { onPreview(version) },
                onDelete: { onDelete(version) }
            )
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct FamiliarProjectArtifactRow: View {
    let artifact: FamiliarArtifact
    let versionCount: Int
    let exportURL: URL?
    let onPreview: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: FamiliarSpacing.medium) {
            Button(action: onPreview) {
                HStack(spacing: FamiliarSpacing.medium) {
                    Image(systemName: artifactIcon)
                        .foregroundStyle(FamiliarTheme.accent)
                    VStack(alignment: .leading, spacing: FamiliarSpacing.xSmall) {
                        Text(artifact.title).foregroundStyle(.primary)
                        Text(detail)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            if let exportURL {
                ShareLink(item: exportURL) {
                    Image(systemName: "square.and.arrow.up")
                        .frame(
                            minWidth: FamiliarControlSize.minimumHitTarget,
                            minHeight: FamiliarControlSize.minimumHitTarget
                        )
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(String(localized: "common.share", defaultValue: "Share"))
            }
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
                    .frame(
                        minWidth: FamiliarControlSize.minimumHitTarget,
                        minHeight: FamiliarControlSize.minimumHitTarget
                    )
            }
            .buttonStyle(.borderless)
        }
    }

    /// Shows the version only once a lineage actually has history: labelling a
    /// single-version deliverable "v1" would imply revisions that do not exist.
    private var detail: String {
        var values = [ByteCountFormatter.string(fromByteCount: artifact.byteSize, countStyle: .file)]
        if versionCount > 1 { values.append("v\(artifact.version)") }
        return values.joined(separator: " · ")
    }

    private var artifactIcon: String {
        switch artifact.format {
        case .markdown: "doc.richtext"
        case .plainText: "doc.text"
        case .docx: "doc.badge.gearshape"
        case .pdf: "doc.fill"
        case .xlsx: "tablecells"
        case .html: "chevron.left.forwardslash.chevron.right"
        }
    }
}

private struct FamiliarProjectConversationsView: View {
    let conversations: [FamiliarConversation]
    let onSelect: (FamiliarConversation) -> Void
    let onDeleteAll: (() -> Void)?

    @State private var confirmsDeleteAll = false

    var body: some View {
        List(conversations) { conversation in
            Button { onSelect(conversation) } label: {
                VStack(alignment: .leading, spacing: FamiliarSpacing.xSmall) {
                    Text(conversation.title).foregroundStyle(.primary)
                    Text(conversation.updatedAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(String(localized: "project.conversations"))
        .toolbar {
            if let onDeleteAll {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        confirmsDeleteAll = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .disabled(conversations.isEmpty)
                    .accessibilityLabel(String(localized: "conversation.delete_all", defaultValue: "Delete All Chats"))
                    .accessibilityIdentifier("conversation.deleteAll")
                    .confirmationDialog(
                        String(localized: "conversation.delete_all.title", defaultValue: "Delete all chats in this project?"),
                        isPresented: $confirmsDeleteAll,
                        titleVisibility: .visible
                    ) {
                        Button(String(localized: "common.delete_all", defaultValue: "Delete All"), role: .destructive) {
                            onDeleteAll()
                        }
                        Button(String(localized: "common.cancel"), role: .cancel) {}
                    } message: {
                        Text(String(
                            localized: "conversation.delete_all.detail",
                            defaultValue: "Messages, attachments, and saved run history in these chats will be deleted from this iPhone."
                        ))
                    }
                }
            }
        }
    }
}

private struct FamiliarProjectRunsView: View {
    let runs: [FamiliarAgentRun]

    var body: some View {
        List(runs) { run in
            NavigationLink {
                FamiliarProjectRunDetailView(run: run)
            } label: {
                FamiliarProjectRunRow(run: run)
            }
        }
        .navigationTitle(String(localized: "project.runs", defaultValue: "Runs"))
    }
}

private struct FamiliarProjectRunRow: View {
    let run: FamiliarAgentRun

    var body: some View {
        HStack(spacing: FamiliarSpacing.medium) {
            Image(systemName: statusIcon)
                .foregroundStyle(statusColor)
            VStack(alignment: .leading, spacing: FamiliarSpacing.xSmall) {
                Text(runTitle)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(run.startedAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var runTitle: String {
        let snapshot = run.contextSnapshot
        let providerID = snapshot?.providerID ?? ""
        let modelID = snapshot?.modelID ?? ""
        let providerName = FamiliarProviderCatalog.descriptor(for: providerID)?.displayName ?? providerID
        let modelName = FamiliarProviderCatalog.descriptor(for: providerID)?.model(for: modelID).displayName ?? modelID
        return [providerName, modelName].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private var statusIcon: String {
        switch run.status {
        case .running: "bolt.fill"
        case .completed: "checkmark.circle.fill"
        case .cancelled: "xmark.circle"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    private var statusColor: Color {
        switch run.status {
        case .running: FamiliarTheme.accent
        case .completed: .green
        case .cancelled: .secondary
        case .failed: .red
        }
    }
}

private struct FamiliarProjectRunDetailView: View {
    @Query(sort: \FamiliarRunSkillSnapshotRecord.sequence) private var allSkillSnapshots: [FamiliarRunSkillSnapshotRecord]
    @Query private var activities: [FamiliarActivityRecord]
    @Query private var approvals: [FamiliarApprovalRecord]
    @Query private var results: [FamiliarToolResultRecord]
    @Query private var invocations: [FamiliarToolInvocationRecord]
    let run: FamiliarAgentRun

    init(run: FamiliarAgentRun) {
        self.run = run
        let runtimeID = run.runtimeID
        _activities = Query(
            filter: #Predicate<FamiliarActivityRecord> { $0.runtimeID == runtimeID },
            sort: \FamiliarActivityRecord.sequence
        )
        _approvals = Query(
            filter: #Predicate<FamiliarApprovalRecord> { $0.runtimeID == runtimeID },
            sort: \FamiliarApprovalRecord.requestedAt
        )
        _results = Query(
            filter: #Predicate<FamiliarToolResultRecord> { $0.runtimeID == runtimeID },
            sort: \FamiliarToolResultRecord.createdAt
        )
        _invocations = Query(
            filter: #Predicate<FamiliarToolInvocationRecord> { $0.runtimeID == runtimeID },
            sort: \FamiliarToolInvocationRecord.startedAt
        )
    }

    var body: some View {
        List {
            Section(String(localized: "project.run.execution", defaultValue: "Execution")) {
                LabeledContent(String(localized: "project.run.status", defaultValue: "Status"), value: statusText)
                LabeledContent(String(localized: "settings.provider"), value: providerName)
                LabeledContent(String(localized: "settings.model"), value: modelName)
                LabeledContent(String(localized: "project.run.started", defaultValue: "Started")) {
                    Text(run.startedAt, format: .dateTime.year().month().day().hour().minute().second())
                }
                if let finishedAt = run.finishedAt {
                    LabeledContent(String(localized: "project.run.finished", defaultValue: "Finished")) {
                        Text(finishedAt, format: .dateTime.year().month().day().hour().minute().second())
                    }
                }
                if let reason = run.finishReason, !reason.isEmpty {
                    LabeledContent(String(localized: "settings.runs.result", defaultValue: "Result"), value: reason)
                }
                if let finishedAt = run.finishedAt {
                    LabeledContent(String(localized: "project.run.duration", defaultValue: "Duration")) {
                        Text(finishedAt.timeIntervalSince(run.startedAt), format: .number.precision(.fractionLength(1)))
                        + Text(" s")
                    }
                }
            }

            Section(String(localized: "project.run.steps", defaultValue: "Execution Steps")) {
                if toolActivities.isEmpty {
                    Text(String(localized: "settings.runs.no_activities", defaultValue: "No persisted activities"))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(toolActivities) { activity in
                        FamiliarProjectRunStep(
                            activity: activity,
                            invocation: invocations.first { $0.activityID == activity.activityID },
                            approval: approvals.first { $0.activityID == activity.activityID },
                            result: results.first { $0.activityID == activity.activityID }
                        )
                    }
                }
            }

            if !approvals.isEmpty {
                Section(String(localized: "project.run.authorizations", defaultValue: "Authorizations")) {
                    ForEach(approvals) { approval in
                        FamiliarProjectRunApproval(approval: approval)
                    }
                }
            }

            Section(String(localized: "project.run.resources", defaultValue: "Resources Used")) {
                if resourceReferences.isEmpty {
                    Text(String(localized: "project.run.resources.empty", defaultValue: "No project resources were used."))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(resourceReferences, id: \.id) { reference in
                        VStack(alignment: .leading, spacing: FamiliarSpacing.xSmall) {
                            Text(reference.filename)
                            Text("v\(reference.version) · \(String(reference.contentHash.prefix(12)))")
                                .font(.caption.monospaced()).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section(String(localized: "project.run.skills", defaultValue: "Skills Used")) {
                if skillSnapshots.isEmpty {
                    Text(String(localized: "project.run.skills.empty", defaultValue: "No Skills were used."))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(skillSnapshots) { skill in
                        VStack(alignment: .leading, spacing: FamiliarSpacing.xSmall) {
                            Text(skill.name)
                            Text("\(skill.stableID) · v\(skill.version) · \(String(skill.contentHash.prefix(12)))")
                                .font(.caption.monospaced()).foregroundStyle(.secondary)
                            if !skill.allowedTools.isEmpty {
                                Text(skill.allowedTools.joined(separator: ", "))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Section(String(localized: "project.run.tools", defaultValue: "Available Tools")) {
                if toolNames.isEmpty {
                    Text(String(localized: "project.run.tools.empty", defaultValue: "No tools were exposed."))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(toolNames, id: \.self) { toolName in
                        Label(toolName, systemImage: "wrench.and.screwdriver")
                    }
                }
            }
        }
        .navigationTitle(String(localized: "project.run", defaultValue: "Run"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var snapshot: FamiliarContextSnapshotRecord? { run.contextSnapshot }
    private var toolActivities: [FamiliarActivityRecord] {
        activities.filter { $0.kind == .tool }
    }
    private var providerName: String {
        guard let snapshot else { return String(localized: "common.unknown", defaultValue: "Unknown") }
        return FamiliarProviderCatalog.descriptor(for: snapshot.providerID)?.displayName ?? snapshot.providerID
    }
    private var modelName: String {
        guard let snapshot else { return String(localized: "common.unknown", defaultValue: "Unknown") }
        return FamiliarProviderCatalog.descriptor(for: snapshot.providerID)?.model(for: snapshot.modelID).displayName ?? snapshot.modelID
    }
    private var resourceReferences: [FamiliarContextResourceReference] {
        snapshot?.resourceReferences.sorted {
            $0.filename == $1.filename ? $0.version < $1.version : $0.filename.localizedStandardCompare($1.filename) == .orderedAscending
        } ?? []
    }
    private var toolNames: [String] {
        guard let data = snapshot?.exposedToolNamesJSON.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return decoded.sorted()
    }
    private var skillSnapshots: [FamiliarRunSkillSnapshotRecord] {
        allSkillSnapshots.filter { $0.runID == run.id }.sorted { $0.sequence < $1.sequence }
    }
    private var statusText: String {
        switch run.status {
        case .running: String(localized: "project.run.status.running", defaultValue: "Running")
        case .completed: String(localized: "project.run.status.completed", defaultValue: "Completed")
        case .cancelled: String(localized: "project.run.status.cancelled", defaultValue: "Cancelled")
        case .failed: String(localized: "project.run.status.failed", defaultValue: "Failed")
        }
    }
}

private struct FamiliarProjectRunStep: View {
    let activity: FamiliarActivityRecord
    let invocation: FamiliarToolInvocationRecord?
    let approval: FamiliarApprovalRecord?
    let result: FamiliarToolResultRecord?

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: FamiliarSpacing.small) {
                LabeledContent(String(localized: "project.run.step.call_id", defaultValue: "Call ID"), value: activity.toolCallID ?? String(localized: "common.unknown", defaultValue: "Unknown"))
                LabeledContent(String(localized: "project.run.step.effect", defaultValue: "Effect"), value: activity.effect?.rawValue ?? FamiliarToolEffect.read.rawValue)
                LabeledContent(String(localized: "project.run.started", defaultValue: "Started")) {
                    Text(activity.startedAt, format: .dateTime.year().month().day().hour().minute().second())
                }
                if let endedAt = activity.endedAt {
                    LabeledContent(String(localized: "project.run.finished", defaultValue: "Finished")) {
                        Text(endedAt, format: .dateTime.year().month().day().hour().minute().second())
                    }
                }
                if let invocation {
                    LabeledContent(String(localized: "project.run.step.invocation", defaultValue: "Invocation"), value: invocation.state.rawValue)
                    LabeledContent(String(localized: "project.run.step.arguments_hash", defaultValue: "Arguments hash")) {
                        Text(invocation.argumentsHash)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                }
                if let failureCode = activity.failureCode {
                    LabeledContent(String(localized: "project.run.step.failure_code", defaultValue: "Failure code"), value: failureCode)
                    if let retryable = activity.failureRetryable {
                        LabeledContent(String(localized: "project.run.step.retryable", defaultValue: "Retryable"), value: retryable ? String(localized: "common.yes", defaultValue: "Yes") : String(localized: "common.no", defaultValue: "No"))
                    }
                }
                if let detail = activity.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                if let approval {
                    Divider()
                    Label(authorizationSummary(approval), systemImage: "hand.raised")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let result {
                    Divider()
                    LabeledContent(String(localized: "project.run.step.payload", defaultValue: "Result payload"), value: result.payloadName)
                    LabeledContent(String(localized: "project.run.step.payload_hash", defaultValue: "Payload hash")) {
                        Text(result.payloadHash)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                    if let envelope = try? JSONDecoder().decode(FamiliarToolResultEnvelope.self, from: Data(result.envelopeJSON.utf8)) {
                        Text(envelope.summary)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .font(.caption)
            .padding(.vertical, FamiliarSpacing.small)
        } label: {
            HStack(spacing: FamiliarSpacing.medium) {
                Image(systemName: statusSymbol)
                    .foregroundStyle(statusColor)
                    .frame(width: FamiliarIconSize.standard)
                VStack(alignment: .leading, spacing: FamiliarSpacing.xSmall) {
                    Text(activity.toolName.map(FamiliarToolPresentationName.title) ?? activity.summary)
                        .foregroundStyle(.primary)
                    Text(activity.phase.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var statusSymbol: String {
        switch activity.phase {
        case .queued, .running: "circle.dotted"
        case .awaitingApproval: "hand.raised.fill"
        case .awaitingClarification: "questionmark.bubble"
        case .succeeded: "checkmark.circle.fill"
        case .failed: "exclamationmark.circle.fill"
        case .cancelled: "xmark.circle"
        case .undone: "arrow.uturn.backward.circle.fill"
        }
    }

    private var statusColor: Color {
        switch activity.phase {
        case .succeeded: FamiliarAISurfaceColor.success
        case .failed: FamiliarAISurfaceColor.failure
        case .cancelled, .undone: .secondary
        default: FamiliarTheme.accent
        }
    }

    private func authorizationSummary(_ approval: FamiliarApprovalRecord) -> String {
        if approval.automaticAuthorization {
            return String(localized: "project.run.authorization.automatic", defaultValue: "Allowed by a remembered authorization")
        }
        guard approval.decision == .approved else {
            return String(localized: "project.run.authorization.cancelled", defaultValue: "Cancelled by the user")
        }
        return approval.scope?.rawValue ?? FamiliarApprovalScope.once.rawValue
    }
}

private struct FamiliarProjectRunApproval: View {
    let approval: FamiliarApprovalRecord

    var body: some View {
        VStack(alignment: .leading, spacing: FamiliarSpacing.small) {
            HStack {
                Label(FamiliarToolPresentationName.title(for: approval.toolName), systemImage: approval.automaticAuthorization ? "checkmark.shield.fill" : "hand.raised.fill")
                    .font(.headline)
                Spacer(minLength: 0)
                Text(decisionTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(approval.decision == .approved ? FamiliarAISurfaceColor.success : .secondary)
            }
            if let target = approval.target, !target.isEmpty {
                Text(target)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(fields) { field in
                LabeledContent(field.label, value: field.formattedValue)
                    .font(.caption)
            }
            LabeledContent(String(localized: "project.run.authorization.risk", defaultValue: "Risk"), value: approval.risk.rawValue)
                .font(.caption)
            LabeledContent(String(localized: "project.run.authorization.scope", defaultValue: "Scope"), value: approval.scope?.rawValue ?? "-")
                .font(.caption)
            LabeledContent(String(localized: "project.run.authorization.allowed", defaultValue: "Allowed choices"), value: allowedDurations.map(\.rawValue).joined(separator: ", "))
                .font(.caption)
            Text(approval.consequence)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(approval.requestedAt, format: .dateTime.year().month().day().hour().minute().second())
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, FamiliarSpacing.xSmall)
    }

    private var fields: [FamiliarApprovalField] {
        (try? JSONDecoder().decode([FamiliarApprovalField].self, from: Data(approval.orderedFieldsJSON.utf8))) ?? []
    }

    private var allowedDurations: [FamiliarAuthorizationDuration] {
        (try? JSONDecoder().decode([FamiliarAuthorizationDuration].self, from: Data(approval.allowedAuthorizationDurationsJSON.utf8))) ?? []
    }

    private var decisionTitle: String {
        if approval.automaticAuthorization {
            return String(localized: "project.run.authorization.automatic.short", defaultValue: "Automatic")
        }
        return switch approval.decision {
        case .approved: String(localized: "approval.sent", defaultValue: "Approved")
        case .cancelled: String(localized: "settings.runs.cancelled", defaultValue: "Cancelled")
        case nil: String(localized: "agent.status.awaiting_confirmation", defaultValue: "Awaiting approval")
        }
    }
}

private enum FamiliarProjectResourceEntryDestination: String, Identifiable {
    case webPage
    case pastedText
    var id: String { rawValue }
}

private struct FamiliarProjectResourceEntryView: View {
    @Environment(\.dismiss) private var dismiss
    let destination: FamiliarProjectResourceEntryDestination
    let onImport: (String, String) -> Void

    @State private var title = ""
    @State private var value = ""

    var body: some View {
        NavigationStack {
            Form {
                if destination == .pastedText {
                    TextField(String(localized: "resource.text_title", defaultValue: "Title (optional)"), text: $title)
                }
                Section {
                    if destination == .webPage {
                        TextField("https://example.com", text: $value)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } else {
                        TextEditor(text: $value)
                            .frame(minHeight: 220)
                    }
                } footer: {
                    if destination == .webPage {
                        Text(String(localized: "resource.web.footer", defaultValue: "Only public HTTPS pages supported by Familiar's safe web fetcher can be imported."))
                    }
                }
            }
            .navigationTitle(destination == .webPage
                             ? String(localized: "resource.add_web", defaultValue: "Add Web Page")
                             : String(localized: "resource.add_text", defaultValue: "Paste Text"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "resource.import", defaultValue: "Import")) {
                        onImport(title, value)
                        dismiss()
                    }
                    .disabled(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

private struct FamiliarProjectPreviewDocument: Identifiable {
    let id = UUID()
    let url: URL
    let format: FamiliarArtifactFormat?
}

private extension FamiliarProjectResourceService {
    static func latestVersion(of resource: FamiliarResource) -> FamiliarResourceVersion? {
        resource.versions.max {
            $0.version == $1.version ? $0.createdAt < $1.createdAt : $0.version < $1.version
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
    /// Empty string means "follow the global selection", which is the stored `nil`.
    @State private var modelIDOverride: String
    @State private var errorMessage: String?

    init(destination: FamiliarProjectEditorDestination, onSave: @escaping (FamiliarProject) -> Void) {
        self.destination = destination
        self.onSave = onSave
        switch destination {
        case .create:
            _name = State(initialValue: "")
            _summary = State(initialValue: "")
            _instruction = State(initialValue: "")
            _modelIDOverride = State(initialValue: "")
        case .edit(let project):
            _name = State(initialValue: project.name)
            _summary = State(initialValue: project.summary)
            _instruction = State(initialValue: project.instruction?.text ?? "")
            _modelIDOverride = State(initialValue: project.modelIDOverride ?? "")
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
                Section {
                    Picker(String(localized: "project.model", defaultValue: "Model"), selection: $modelIDOverride) {
                        Text(String(localized: "project.model.follow_global", defaultValue: "Follow global setting")).tag("")
                        ForEach(FamiliarProviderCatalog.deepSeek.curatedModels) { model in
                            Text(model.displayName).tag(model.id)
                        }
                    }
                } footer: {
                    Text(String(localized: "project.model.footer", defaultValue: "Runs started in this project use this model. Everything else keeps the global selection."))
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
            try service.updateModelOverride(project, modelID: modelIDOverride, in: modelContext)
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
