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

    @State private var path: [UUID]
    @State private var editor: FamiliarProjectEditorDestination?
    @State private var errorMessage: String?

    init(
        initialProjectID: UUID? = nil,
        registry: FamiliarToolRegistry? = nil,
        onConversationRequest: @escaping (FamiliarProjectConversationRequest) -> Void
    ) {
        self.initialProjectID = initialProjectID
        self.registry = registry
        self.onConversationRequest = onConversationRequest
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
                        onDelete: { resourceToDelete = $0 }
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
                        onSelect: { onConversationRequest(.open(conversationID: $0.id)) }
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
    private var sortedResources: [FamiliarResource] { project.resources.sorted { $0.updatedAt > $1.updatedAt } }
    private var sortedConversations: [FamiliarConversation] { project.conversations.sorted { $0.updatedAt > $1.updatedAt } }
    private var sortedRuns: [FamiliarAgentRun] { project.agentRuns.sorted { $0.startedAt > $1.startedAt } }
    private var recentResources: [FamiliarResource] { Array(sortedResources.prefix(3)) }
    private var recentArtifacts: [FamiliarArtifact] { Array(projectArtifacts.prefix(3)) }

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

    var body: some View {
        List(resources) { resource in
            FamiliarProjectResourceRow(
                resource: resource,
                onPreview: { onPreview(resource) },
                onDelete: { onDelete(resource) }
            )
        }
        .navigationTitle(String(localized: "resource.section"))
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

    var body: some View {
        List(artifacts) { artifact in
            FamiliarProjectArtifactRow(
                artifact: artifact,
                exportURL: FamiliarArtifactService().exportURL(for: artifact),
                onPreview: { onPreview(artifact) },
                onDelete: { onDelete(artifact) }
            )
        }
        .navigationTitle(String(localized: "artifact.section", defaultValue: "Artifacts"))
    }
}

private struct FamiliarProjectArtifactRow: View {
    let artifact: FamiliarArtifact
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
                        Text(ByteCountFormatter.string(fromByteCount: artifact.byteSize, countStyle: .file))
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
    let run: FamiliarAgentRun

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
