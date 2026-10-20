import SwiftData
import SwiftUI
import UniformTypeIdentifiers

enum FamiliarProjectConversationRequest: Equatable, Sendable {
    case open(conversationID: UUID)
    case create(projectID: UUID)
}

private enum FamiliarProjectRoute: Hashable { case project(UUID), chat(UUID) }

struct FamiliarProjectsView<ChatContent: View>: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FamiliarProject.updatedAt, order: .reverse) private var projects: [FamiliarProject]

    let initialProjectID: UUID?
    private let registry: FamiliarToolRegistry?
    private let onConversationRequest: (FamiliarProjectConversationRequest, @escaping () -> Void) -> Void
    private let chatContent: () -> ChatContent
    private let onChatVisibilityChange: (Bool) -> Void
    private let onDeleteConversations: (([FamiliarConversation]) -> Void)?

    @State private var path: [FamiliarProjectRoute]
    @State private var editor: FamiliarProjectEditorDestination?
    @State private var errorMessage: String?
    @Binding private var requestedProjectDetailsID: UUID?

    init(
        initialProjectID: UUID? = nil, requestedProjectDetailsID: Binding<UUID?>, registry: FamiliarToolRegistry? = nil,
        onConversationRequest: @escaping (FamiliarProjectConversationRequest, @escaping () -> Void) -> Void,
        onDeleteConversations: @escaping ([FamiliarConversation]) -> Void,
        onChatVisibilityChange: @escaping (Bool) -> Void,
        @ViewBuilder chatContent: @escaping () -> ChatContent
    ) {
        self.initialProjectID = initialProjectID; self.registry = registry
        _requestedProjectDetailsID = requestedProjectDetailsID
        self.onConversationRequest = onConversationRequest; self.onDeleteConversations = onDeleteConversations
        self.onChatVisibilityChange = onChatVisibilityChange; self.chatContent = chatContent
        _path = State(initialValue: initialProjectID.map { [.project($0)] } ?? [])
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
            .navigationDestination(for: FamiliarProjectRoute.self) { route in
                switch route {
                case .chat:
                    chatContent()
                        .toolbar(.visible, for: .navigationBar)
                case .project(let projectID):
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
        }
        .onChange(of: path) { _, path in
            onChatVisibilityChange(path.contains { route in if case .chat = route { return true }; return false })
        }
        .onChange(of: requestedProjectDetailsID) { _, projectID in
            guard let projectID else { return }
            path = [.project(projectID)]
            requestedProjectDetailsID = nil
        }
        .onDisappear { onChatVisibilityChange(false) }
        .sheet(item: $editor) { destination in
            FamiliarProjectEditorView(destination: destination) { project in
                editor = nil
                if path.last != .project(project.id) { path.append(.project(project.id)) }
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
                NavigationLink(value: FamiliarProjectRoute.project(project.id)) {
                    VStack(alignment: .leading, spacing: FamiliarSpacing.xSmall) {
                        Text(project.displayName)
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
                .accessibilityIdentifier("project.open.\(project.id)")
            }
        }
    }

    private func handleConversationRequest(_ request: FamiliarProjectConversationRequest) {
        onConversationRequest(request) {
            path.append(.chat(UUID()))
        }
    }

}

struct FamiliarProjectDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \FamiliarFileRecord.updatedAt, order: .reverse) private var fileRecords: [FamiliarFileRecord]

    let project: FamiliarProject
    let registry: FamiliarToolRegistry?
    let onConversationRequest: (FamiliarProjectConversationRequest) -> Void
    let onDeleteConversations: (([FamiliarConversation]) -> Void)?
    let onEdit: () -> Void
    let onError: (String) -> Void

    @State private var showsResourceImporter = false
    @State private var resourceEntry: FamiliarProjectResourceEntryDestination?
    @State private var isImportingResource = false
    @State private var confirmsProjectDeletion = false

    var body: some View {
        List {
            Section {
                Button {
                    onConversationRequest(.create(projectID: project.id))
                } label: {
                    Label(String(localized: "project.new_chat"), systemImage: "square.and.pencil")
                }
                .disabled(project.status != .active)
                .accessibilityIdentifier("project.newChat")
            }
            if !project.summary.isEmpty {
                Section {
                    FamiliarProjectHero(project: project)
                }
            }

            projectContextSection
            projectConfigurationSection

            Section {
                NavigationLink {
                    FamiliarFilesView(scope: .project(project.id))
                } label: {
                    HStack {
                        Label(String(localized: "chat.files"), systemImage: "folder")
                        Spacer()
                        Text(fileRecords.count { $0.scopeKey == FamiliarWorkScope.project(project.id).storageKey }, format: .number)
                            .foregroundStyle(.secondary)
                    }
                }
                resourceImportMenu
                if isImportingResource {
                    Label(String(localized: "resource.importing"), systemImage: "arrow.down.doc")
                }
            }

        }
        .navigationTitle(project.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
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

    private var projectContextSection: some View {
        Section(String(localized: "project.context", defaultValue: "Project Context")) {
            // First item: the instruction used to live in the hero block above. It belongs
            // here because it is project context, and tapping it opens the same editor that
            // owns it rather than duplicating an editing surface.
            Button(action: onEdit) {
                HStack(spacing: FamiliarSpacing.small) {
                    FamiliarProjectContextRow(
                        title: String(localized: "project.instruction"),
                        detail: project.instruction?.text ?? String(localized: "project.instruction.empty"),
                        symbol: "text.quote", color: .pink, count: nil
                    )
                    Image(systemName: "chevron.right")
                        .font(FamiliarTypography.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
                .frame(minHeight: FamiliarControlSize.minimumHitTarget)
            }
            .buttonStyle(.plain)

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
                    symbol: "bubble.left.and.bubble.right", color: .blue,
                    count: sortedConversations.count
                )
            }

            NavigationLink {
                FamiliarMemorySettingsView(scope: .project(project.id), showsGlobalControl: false,
                    isAutomaticMemoryEnabled: .constant(FamiliarSettingsStore.load().isAutomaticMemoryEnabled))
            } label: {
                FamiliarProjectContextRow(title: String(localized: "settings.memory.title"), detail: "",
                    symbol: "brain", color: .pink, count: nil)
            }
            NavigationLink { FamiliarRunRecordList(runs: sortedRuns) } label: {
                FamiliarProjectContextRow(title: String(localized: "project.runs"), detail: "",
                    symbol: "clock.arrow.circlepath", color: .gray, count: sortedRuns.count)
            }
        }
    }

    private var projectConfigurationSection: some View {
        Section(String(localized: "project.configuration")) {
                NavigationLink {
                    FamiliarProjectEnvironmentView(projectID: project.id)
                } label: {
                    FamiliarProjectContextRow(
                        title: String(localized: "project.environment", defaultValue: "Environment"),
                        detail: String(localized: "project.environment.detail", defaultValue: "Dependencies for advanced file tasks"),
                        symbol: "shippingbox", color: .gray,
                        count: nil
                    )
                }

                NavigationLink {
                    FamiliarProjectSkillsView(projectID: project.id)
                } label: {
                    FamiliarProjectContextRow(
                        title: String(localized: "settings.skills.title", defaultValue: "Skills"),
                        detail: String(localized: "project.skills.context_detail", defaultValue: "Guidance available for this Project"),
                        symbol: "wand.and.stars", color: .purple,
                        count: nil
                    )
                }

                NavigationLink {
                    FamiliarMCPSettingsView(projectID: project.id)
                } label: {
                    FamiliarProjectContextRow(title: String(localized: "mcp.title"), detail: String(localized: "mcp.settings.detail"), symbol: "wrench.and.screwdriver", color: .blue, count: nil)
                }

                if let registry {
                    NavigationLink {
                        FamiliarProjectCapabilitiesView(projectID: project.id, registry: registry)
                    } label: {
                        FamiliarProjectContextRow(
                            title: String(localized: "project.capabilities", defaultValue: "Capabilities"),
                            detail: String(localized: "project.capabilities.detail", defaultValue: "Choose the tools this Project can use"),
                            symbol: "switch.2", color: .blue,
                            count: nil
                        )
                    }
                }
        }
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
                Text(String(localized: "resource.add"))
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

    private var deleteAllConversations: (() -> Void)? {
        guard let onDeleteConversations else { return nil }
        let project = project
        return { onDeleteConversations(project.conversations) }
    }

    private var sortedConversations: [FamiliarConversation] { project.conversations.sorted { $0.updatedAt > $1.updatedAt } }
    private var sortedRuns: [FamiliarAgentRun] { project.agentRuns.sorted { $0.startedAt > $1.startedAt } }

    /// One entry per deliverable: taking the first three rows flatly would show v3, v2
    /// and v1 of the same file as three separate recent files.







    private func importResource(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            isImportingResource = true
            Task {
                defer { isImportingResource = false }
                do {
                    try await FamiliarFileImportService().importDocument(from: url, into: project, in: modelContext)
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
                    try await FamiliarFileImportService().importWebPage(
                        from: value,
                        into: project,
                        in: modelContext
                    )
                case .pastedText:
                    try FamiliarFileImportService().importPastedText(
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
    @Query(sort: \FamiliarEnvironmentRecord.preparedAt, order: .reverse)
    private var records: [FamiliarEnvironmentRecord]
    let projectID: UUID

    var body: some View {
        List {
            if let record = records.first(where: { $0.scope == .project(projectID) }) {
                Section(String(localized: "project.environment", defaultValue: "Environment")) {
                    LabeledContent(String(localized: "environment.state", defaultValue: "State"), value: record.state.rawValue)
                    LabeledContent(String(localized: "environment.python", defaultValue: "Python"), value: record.pythonVersion)
                    LabeledContent(String(localized: "environment.revision", defaultValue: "Revision"), value: record.revision.uuidString)
                    LabeledContent(String(localized: "environment.size", defaultValue: "Size"), value: ByteCountFormatter.string(fromByteCount: record.byteSize, countStyle: .file))
                    LabeledContent(String(localized: "environment.lock", defaultValue: "Lock"), value: String(record.lockHash.prefix(16)))
                }
                Section(String(localized: "environment.packages", defaultValue: "Resolved Packages")) {
                    ForEach(decodedPackages(record), id: \.self) { package in
                        Text(package).font(FamiliarTypography.body.monospaced())
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

    private func decodedPackages(_ record: FamiliarEnvironmentRecord) -> [String] {
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
                        Text(skill.descriptionText).font(FamiliarTypography.caption).foregroundStyle(.secondary)
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
    @State private var saveError: String?
    @State private var unavailable: [String: String] = [:]

    var body: some View {
        List {
            if let saveError {
                Section { Text(saveError).foregroundStyle(FamiliarTheme.failure).accessibilityIdentifier("capabilities.save-error") }
            }
            // Grouped by category so a 50-plus tool list is scannable. Category order comes
            // from the enum's declaration order, not from whatever order the registry
            // happens to return, so the screen does not reshuffle between launches.
            ForEach(FamiliarToolGroup.allCases, id: \.self) { category in
                let group = manifests.filter { FamiliarToolGroup.group(for: $0.name) == category }
                if !group.isEmpty {
                    Section(category.title) {
                        ForEach(group, id: \.id) { manifest in
                            capabilityToggle(manifest)
                        }
                    }
                }
            }
        }
        .navigationTitle(String(localized: "project.capabilities", defaultValue: "Capabilities"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            manifests = await registry.snapshot()
            let report = await registry.availabilityReport()
            unavailable = Dictionary(report.unavailable.map { ($0.name, $0.reason) }, uniquingKeysWith: { _, latest in latest })
        }
    }

    private func capabilityToggle(_ manifest: FamiliarToolManifest) -> some View {
        Toggle(isOn: Binding(
            get: { isEnabled(manifest.id) },
            set: { enabled in
                do {
                    try FamiliarProjectService().setCapability(
                    manifest.id,
                    enabled: enabled,
                    allCapabilities: manifests,
                    projectID: projectID,
                    in: modelContext
                )
                    saveError = nil
                } catch { saveError = error.localizedDescription }
            }
        )) {
            VStack(alignment: .leading, spacing: FamiliarSpacing.xSmall) {
                Text(FamiliarToolPresentationName.title(for: manifest.name))
                Text(FamiliarToolPresentationName.effectDescription(manifest)).font(FamiliarTypography.caption).foregroundStyle(.secondary).lineLimit(2)
                if let reason = unavailable[manifest.name] { Text(reason).font(FamiliarTypography.caption).foregroundStyle(FamiliarTheme.inkSecondary) }
            }
        }
        .disabled(FamiliarToolGroup.baseToolNames.contains(manifest.name))
    }

    private func isEnabled(_ id: String) -> Bool {
        let projectBindings = allBindings.filter { $0.projectID == projectID }
        if let manifest = manifests.first(where: { $0.id == id }), FamiliarToolGroup.baseToolNames.contains(manifest.name) { return true }
        guard !projectBindings.isEmpty else {
            return manifests.first(where: { $0.id == id }).map { FamiliarToolGroup.isDefaultEnabled($0.name) } ?? false
        }
        return projectBindings.first { $0.capabilityID == id }?.enabled == true
    }
}

private struct FamiliarProjectHero: View {
    let project: FamiliarProject

    var body: some View {
        // Summary only: the instruction moved into Project Context, where it belongs, and
        // showing it in both places would leave two things to keep in sync.
        Text(project.summary)
            .font(FamiliarTypography.body)
            .foregroundStyle(.secondary)
            .padding(.vertical, FamiliarSpacing.small)
    }
}

private struct FamiliarProjectContextRow: View {
    let title: String
    let detail: String
    let symbol: String
    var color: Color = FamiliarTheme.accent
    let count: Int?

    var body: some View {
        HStack(spacing: FamiliarSpacing.medium) {
            FamiliarSettingsRowIcon(symbol: symbol, color: color)

            VStack(alignment: .leading, spacing: FamiliarSpacing.xSmall) {
                Text(title)
                    .font(FamiliarTypography.body)
                    .foregroundStyle(.primary)
                if count == nil, !detail.isEmpty {
                    Text(detail).font(FamiliarTypography.caption).foregroundStyle(.secondary).lineLimit(2)
                }
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

struct FamiliarProjectConversationsView: View {
    let conversations: [FamiliarConversation]
    let onSelect: (FamiliarConversation) -> Void
    let onDeleteAll: (() -> Void)?
    var title: String = String(localized: "project.conversations")

    @State private var confirmsDeleteAll = false

    var body: some View {
        List(conversations) { conversation in
            Button { onSelect(conversation) } label: {
                VStack(alignment: .leading, spacing: FamiliarSpacing.xSmall) {
                    Text(conversation.title).foregroundStyle(.primary)
                    Text(conversation.updatedAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                        .font(FamiliarTypography.caption).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(title)
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



enum FamiliarProjectEditorDestination: Identifiable {
    case create
    case edit(FamiliarProject)

    var id: String {
        switch self {
        case .create: "create"
        case .edit(let project): "edit-\(project.id.uuidString)"
        }
    }
}

struct FamiliarProjectEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let destination: FamiliarProjectEditorDestination
    let onSave: (FamiliarProject) -> Void

    @State private var name: String
    @State private var summary: String
    @State private var instruction: String
    /// Empty string means "follow the global selection", which is the stored `nil`.
    @State private var modelIDOverride: String
    @State private var providerIDOverride: String = FamiliarProviderCatalog.deepSeek.id
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
            _name = State(initialValue: project.displayName)
            _providerIDOverride = State(initialValue: project.providerIDOverride ?? FamiliarProviderCatalog.deepSeek.id)
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
                    Picker(String(localized: "settings.provider"), selection: $providerIDOverride) {
                        ForEach(FamiliarProviderCatalog.builtIn) { provider in
                            Text(provider.displayName).tag(provider.id)
                        }
                    }
                    .onChange(of: providerIDOverride) { _, _ in modelIDOverride = "" }
                    Picker(String(localized: "project.model", defaultValue: "Model"), selection: $modelIDOverride) {
                        Text(String(localized: "project.model.follow_global", defaultValue: "Follow global setting")).tag("")
                        ForEach(FamiliarProviderCatalog.descriptor(for: providerIDOverride)?.curatedModels ?? []) { model in
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
                        .font(FamiliarTypography.caption.monospacedDigit())
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
            try service.updateModelOverride(project, modelID: modelIDOverride, providerID: providerIDOverride, in: modelContext)
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

private enum FamiliarProjectResourceEntryDestination: String, Identifiable {
    case webPage
    case pastedText
    var id: String { rawValue }
}
