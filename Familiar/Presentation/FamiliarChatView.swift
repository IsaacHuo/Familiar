import SwiftData
import SwiftUI

struct FamiliarChatView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \FamiliarConversation.updatedAt, order: .reverse)
    private var conversations: [FamiliarConversation]

    @State private var controller: FamiliarChatController
    @StateObject private var speechTranscriber = FamiliarSpeechTranscriber()
    @State private var isDrawerOpen = false
    @State private var drawerDrag: CGFloat = 0
    @State private var isDragging = false
    @State private var presentedSheet: FamiliarSheetDestination?
    @State private var renameRequest: FamiliarRenameRequest?
    @State private var pendingMessageOperation: FamiliarPendingMessageOperation?
    @State private var speechBaseDraft = ""
    @State private var configuredProviderIDs: Set<String> = []
    @FocusState private var isComposerFocused: Bool
    private let onRestartOnboarding: () -> Void
    @Binding private var pendingDeepLink: FamiliarDeepLink?

    init(
        dependencies: FamiliarAppDependencies,
        onRestartOnboarding: @escaping () -> Void,
        pendingDeepLink: Binding<FamiliarDeepLink?>
    ) {
        _controller = State(initialValue: FamiliarChatController(dependencies: dependencies))
        self.onRestartOnboarding = onRestartOnboarding
        _pendingDeepLink = pendingDeepLink
    }

    var body: some View {
        @Bindable var controller = controller
        GeometryReader { safeGeometry in
            let safeAreaInsets = safeGeometry.safeAreaInsets
            let keyboardHeight = max(UIScreen.main.bounds.height - safeGeometry.size.height, 0)
            let bottomInset = keyboardHeight > 0 ? 0 : safeAreaInsets.bottom

            GeometryReader { geometry in
                let drawerWidth = geometry.size.width * 2 / 3
                let visibleDrawerWidth = drawerOffset(width: drawerWidth)
                let drawerProgress = visibleDrawerWidth / max(drawerWidth, 1)
                let cornerRadius = FamiliarTheme.displayCornerRadius * drawerProgress

                ZStack(alignment: .leading) {
                    FamiliarTheme.drawerFill
                        .ignoresSafeArea()

                    FamiliarConversationDrawer(
                        conversations: conversations,
                        selectedConversationID: controller.selectedConversationID,
                        safeAreaInsets: safeAreaInsets,
                        onSelect: { conversation in
                            speechTranscriber.stop()
                            controller.select(conversation.id, in: modelContext)
                            closeDrawer()
                        },
                        onRename: { conversation in
                            renameRequest = FamiliarRenameRequest(
                                conversation: conversation,
                                title: conversation.title
                            )
                        },
                        onDelete: { conversation in
                            controller.delete([conversation], in: modelContext)
                        }
                    )
                    .frame(width: drawerWidth)
                    .offset(x: -(drawerWidth * 0.12) * (1 - drawerProgress))

                    ZStack {
                        UnevenRoundedRectangle(
                            topLeadingRadius: cornerRadius,
                            bottomLeadingRadius: cornerRadius,
                            bottomTrailingRadius: 0,
                            topTrailingRadius: 0,
                            style: .continuous
                        )
                        .fill(Color(uiColor: .systemBackground))

                        mainSurface(availableHeight: geometry.size.height - safeAreaInsets.top - bottomInset)
                            .padding(.top, safeAreaInsets.top)
                            .padding(.bottom, bottomInset)
                    }
                    .clipShape(
                        UnevenRoundedRectangle(
                            topLeadingRadius: cornerRadius,
                            bottomLeadingRadius: cornerRadius,
                            bottomTrailingRadius: 0,
                            topTrailingRadius: 0,
                            style: .continuous
                        )
                    )
                    .shadow(color: .black.opacity(0.13 * drawerProgress), radius: 18, x: -7, y: 0)
                    .overlay {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { closeDrawer() }
                            .allowsHitTesting(drawerProgress > 0.01)
                    }
                    .offset(x: visibleDrawerWidth)
                    .simultaneousGesture(drawerGesture(width: drawerWidth))

                    Color.clear
                        .contentShape(Rectangle())
                        .frame(width: 30)
                        .frame(maxHeight: .infinity)
                        .gesture(drawerGesture(width: drawerWidth))
                        .allowsHitTesting(!isDrawerOpen)
                        .zIndex(100)
                        .accessibilityHidden(true)
                }
                .background(FamiliarTheme.drawerFill.ignoresSafeArea())
            }
            .ignoresSafeArea(.container)
        }
        .ignoresSafeArea(.keyboard, edges: isDrawerOpen ? .all : [])
        .sheet(item: $presentedSheet, onDismiss: refreshConfiguredProviders) { destination in
            switch destination {
            case .settings:
                FamiliarSettingsView(
                    initialSettings: controller.settings,
                    onSaveSettings: {
                        controller.updateSettings($0, in: modelContext)
                        refreshConfiguredProviders()
                    },
                    onRestartOnboarding: onRestartOnboarding
                )
            }
        }
        .alert(String(localized: "conversation.rename.title"), isPresented: Binding(
            get: { renameRequest != nil },
            set: { if !$0 { renameRequest = nil } }
        )) {
            TextField(String(localized: "conversation.rename.placeholder"), text: renameTitleBinding)
            Button(String(localized: "common.save")) { commitRename() }
            Button(String(localized: "common.cancel"), role: .cancel) {}
        }

        .alert(String(localized: "app.name"), isPresented: Binding(
            get: { controller.errorMessage != nil },
            set: { if !$0 { controller.errorMessage = nil } }
        )) {
            if !configuredProviderIDs.contains(controller.settings.providerID) {
                Button(String(localized: "common.open_settings")) {
                    presentedSheet = .settings
                }
            }
            Button(String(localized: "common.ok"), role: .cancel) {}
        } message: {
            Text(controller.errorMessage ?? String(localized: "error.unknown"))
        }
        .confirmationDialog(
            String(localized: "message.operation.title"),
            isPresented: Binding(
                get: { pendingMessageOperation != nil },
                set: { if !$0 { pendingMessageOperation = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(pendingMessageOperation?.actionTitle ?? "", role: .destructive) {
                performPendingMessageOperation()
            }
            Button(String(localized: "common.cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "message.operation.detail"))
        }
        .onAppear {
            if controller.selectedConversationID == nil,
               let first = conversations.first {
                controller.select(first.id, in: modelContext)
            }
            refreshConfiguredProviders()
            FamiliarAttachmentStore.pruneDrafts(keeping: Set(controller.draftAttachments.map(\.relativePath)))
            FamiliarAttachmentStore.pruneMessageFiles(keeping: Set(
                conversations.flatMap { $0.messages.flatMap { $0.attachments.map(\.relativePath) } }
            ))
            handlePendingDeepLink()
        }
        .onChange(of: speechTranscriber.errorMessage) { _, message in
            if let message { controller.errorMessage = message }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                refreshConfiguredProviders()
            } else {
                speechTranscriber.stop()
            }
        }
        .onChange(of: pendingDeepLink) { _, _ in
            handlePendingDeepLink()
        }
        .onChange(of: controller.isSending) { _, isSending in
            if !isSending {
                handlePendingDeepLink()
            }
        }
    }

    private func handlePendingDeepLink() {
        guard let deepLink = pendingDeepLink,
              controller.openDeepLink(deepLink, conversations: conversations, in: modelContext)
        else { return }

        pendingDeepLink = nil
        speechTranscriber.stop()
        presentedSheet = nil
        closeDrawer()
        switch deepLink {
        case .newDraft:
            isComposerFocused = true
        case .conversation, .run:
            isComposerFocused = false
        }
    }

    @ViewBuilder
    private func mainSurface(availableHeight: CGFloat) -> some View {
        NavigationStack {
            chatBody
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    FamiliarComposer(
                        draft: $controller.draft,
                        images: $controller.draftImages,
                        documents: $controller.draftAttachments,
                        isSending: controller.isSending,
                        isListening: speechTranscriber.isListening,
                        draftScopeID: controller.selectedConversationID,
                        focus: $isComposerFocused,
                        onSpeech: toggleSpeech,
                        onSend: {
                            speechTranscriber.stop()
                            isComposerFocused = false
                            if controller.isSending {
                                controller.cancelSending(in: modelContext)
                            } else {
                                controller.startSending(in: modelContext)
                            }
                        },
                        availableHeight: availableHeight
                    )
                }
                .modifier(FamiliarTopBarInstaller(content: topBar))
                .toolbar(.hidden, for: .navigationBar)
        }
        .background(Color(uiColor: .systemBackground))
    }

    @ViewBuilder
    private var chatBody: some View {
        if controller.messages.isEmpty,
           controller.toolRunRecords.isEmpty,
           controller.pendingConfirmations.isEmpty,
           controller.streamingText.isEmpty,
           controller.agentStatus == nil,
           controller.toolActivities.isEmpty {
            FamiliarEmptyConversationView(
                isProviderConfigured: configuredProviderIDs.contains(controller.settings.providerID),
                onConfigure: { presentedSheet = .settings },
                onPrompt: { prompt in
                    controller.draft = prompt
                    isComposerFocused = true
                }
            )
        } else {
            FamiliarMessageTimeline(
                messages: controller.messages,
                modelSwitches: controller.modelSwitches,
                toolRunRecords: controller.toolRunRecords,
                pendingConfirmations: controller.pendingConfirmations,
                streamingMessageID: controller.streamingMessageID,
                streamingText: controller.streamingText,
                agentStatus: controller.agentStatus,
                toolActivities: controller.toolActivities,
                availableUndoKeys: controller.availableUndoKeys,
                onResolveConfirmation: { request, decision in
                    controller.resolveConfirmation(request, decision: decision)
                },
                onUndo: { controller.undo($0, in: modelContext) },
                onEdit: { pendingMessageOperation = .edit($0) },
                onRetry: { pendingMessageOperation = .retry($0) }
            )
        }
    }

    private var topBar: some View {
        let selectedProvider = controller.settings.selectedProvider
        var providers = FamiliarProviderCatalog.builtIn.filter { configuredProviderIDs.contains($0.id) }
        if configuredProviderIDs.contains(FamiliarProviderCatalog.customProviderID),
           let customProvider = FamiliarProviderCatalog.descriptor(
               for: FamiliarProviderCatalog.customProviderID,
               configuration: controller.settings.providerConfigurations[FamiliarProviderCatalog.customProviderID] ?? .empty
           ) {
            providers.append(customProvider)
        }
        return FamiliarChatTopBar(
            provider: selectedProvider,
            model: controller.settings.selectedModel,
            providerOptions: providers,
            isSending: controller.isSending,
            onOpenDrawer: { setDrawerOpen(true) },
            onSelectModel: { providerID, modelID in
                controller.selectModel(providerID: providerID, modelID: modelID, in: modelContext)
            },
            onConfigure: { presentedSheet = .settings },
            onNewConversation: {
                speechTranscriber.stop()
                _ = controller.createConversation(in: modelContext)
                isComposerFocused = true
            }
        )
    }

    private var renameTitleBinding: Binding<String> {
        Binding(
            get: { renameRequest?.title ?? "" },
            set: { renameRequest?.title = $0 }
        )
    }

    private func drawerOffset(width: CGFloat) -> CGFloat {
        let base = isDrawerOpen ? width : 0
        return min(max(base + drawerDrag, 0), width)
    }

    private func drawerGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .local)
            .onChanged { value in
                let horizontal = abs(value.translation.width)
                let vertical = abs(value.translation.height)
                guard horizontal > vertical || isDragging else { return }
                isDragging = true
                drawerDrag = value.translation.width
            }
            .onEnded { value in
                guard isDragging else { return }
                isDragging = false

                let currentOffset = drawerOffset(width: width)
                let projectedOffset = min(max(currentOffset + (value.predictedEndTranslation.width - value.translation.width), 0), width)
                let shouldOpen = projectedOffset > width * 0.5

                if reduceMotion {
                    drawerDrag = 0
                    isDrawerOpen = shouldOpen
                } else {
                    withAnimation(.interactiveSpring(response: 0.32, dampingFraction: 0.9)) {
                        drawerDrag = 0
                        isDrawerOpen = shouldOpen
                    }
                }
            }
    }

    private func closeDrawer() {
        setDrawerOpen(false)
    }

    private func setDrawerOpen(_ isOpen: Bool) {
        if reduceMotion {
            isDrawerOpen = isOpen
        } else {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
                isDrawerOpen = isOpen
            }
        }
    }

    private func toggleSpeech() {
        if !speechTranscriber.isListening {
            speechBaseDraft = controller.draft
        }
        speechTranscriber.toggle { transcript in
            let separator = speechBaseDraft.isEmpty || transcript.isEmpty ? "" : " "
            controller.draft = speechBaseDraft + separator + transcript
            isComposerFocused = true
        }
    }

    private func refreshConfiguredProviders() {
        configuredProviderIDs = FamiliarKeychainStore.configuredProviderIDs(
            in: FamiliarProviderCatalog.allProviderIDs
        )
    }

    private func commitRename() {
        guard let request = renameRequest else { return }
        controller.rename(request.conversation, to: request.title, in: modelContext)
        renameRequest = nil
    }

    private func performPendingMessageOperation() {
        guard let operation = pendingMessageOperation else { return }
        pendingMessageOperation = nil
        switch operation {
        case .edit(let message):
            controller.prepareToEdit(message, in: modelContext)
            isComposerFocused = true
        case .retry(let message):
            controller.retry(message, in: modelContext)
        }
    }
}

private enum FamiliarSheetDestination: String, Identifiable {
    case settings
    var id: String { rawValue }
}

private struct FamiliarRenameRequest: Identifiable {
    let id: UUID
    let conversation: FamiliarConversation
    var title: String

    init(conversation: FamiliarConversation, title: String) {
        id = conversation.id
        self.conversation = conversation
        self.title = title
    }
}

private enum FamiliarPendingMessageOperation: Identifiable {
    case edit(FamiliarMessageSnapshot)
    case retry(FamiliarMessageSnapshot)

    var id: String {
        switch self {
        case .edit(let message): "edit-\(message.id.uuidString)"
        case .retry(let message): "retry-\(message.id.uuidString)"
        }
    }

    var actionTitle: String {
        switch self {
        case .edit: String(localized: "message.edit_and_resend")
        case .retry: String(localized: "message.retry")
        }
    }
}



private struct FamiliarTopBarInstaller<Bar: View>: ViewModifier {
    let content: Bar

    @ViewBuilder
    func body(content root: Content) -> some View {
        if #available(iOS 26.0, *) {
            root.safeAreaBar(edge: .top) {
                content
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
            }
        } else {
            root.safeAreaInset(edge: .top, spacing: 0) {
                content
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color(uiColor: .systemBackground))
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(FamiliarTheme.separator)
                            .frame(height: 0.5)
                    }
            }
        }
    }
}

private struct FamiliarChatTopBar: View {
    let provider: FamiliarProviderDescriptor
    let model: FamiliarModelDescriptor
    let providerOptions: [FamiliarProviderDescriptor]
    let isSending: Bool
    let onOpenDrawer: () -> Void
    let onSelectModel: (String, String) -> Void
    let onConfigure: () -> Void
    let onNewConversation: () -> Void

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                GlassEffectContainer(spacing: 12) { controls }
            } else {
                controls
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button(action: onOpenDrawer) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 46, height: 46)
            }
            .buttonStyle(.plain)
            .familiarGlassCircle(interactive: true)
            .accessibilityLabel(String(localized: "drawer.open"))

            Button(action: onConfigure) {
                Image(systemName: "gearshape")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 46, height: 46)
            }
            .buttonStyle(.plain)
            .familiarGlassCircle(interactive: true)
            .accessibilityLabel(String(localized: "drawer.settings"))

            Menu {
                if providerOptions.isEmpty {
                    Button(action: onConfigure) {
                        Label(String(localized: "empty.configure"), systemImage: "key")
                    }
                } else {
                    ForEach(providerOptions) { provider in
                        providerMenu(provider)
                    }
                }
            } label: {
                HStack(spacing: 7) {
                    Text(model.displayName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.bold))
                }
                .padding(.horizontal, 17)
                .frame(height: 44)
            }
            .buttonStyle(.plain)
            .familiarGlassSurface(interactive: true)
            .disabled(isSending)
            .accessibilityLabel(String(format: String(localized: "model.current"), provider.displayName, model.displayName))

            Spacer(minLength: 0)

            Button(action: onNewConversation) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 46, height: 46)
            }
            .buttonStyle(.plain)
            .familiarGlassCircle(interactive: true)
            .disabled(isSending)
            .accessibilityLabel(String(localized: "conversation.new"))
        }
    }

    @ViewBuilder
    private func providerMenu(_ provider: FamiliarProviderDescriptor) -> some View {
        let models = models(for: provider)
        if models.isEmpty {
            Button(action: onConfigure) {
                Label(provider.displayName, systemImage: "gearshape")
            }
        } else {
            Menu(provider.displayName) {
                ForEach(models) { model in
                    Button {
                        onSelectModel(provider.id, model.id)
                    } label: {
                        if self.provider.id == provider.id && self.model.id == model.id {
                            Label(model.displayName, systemImage: "checkmark")
                        } else {
                            Text(model.displayName)
                        }
                    }
                }
            }
        }
    }

    private func models(for provider: FamiliarProviderDescriptor) -> [FamiliarModelDescriptor] {
        guard self.provider.id == provider.id,
              !provider.curatedModels.contains(where: { $0.id == model.id })
        else { return provider.curatedModels }
        return [model] + provider.curatedModels
    }
}



private struct FamiliarEmptyConversationView: View {
    let isProviderConfigured: Bool
    let onConfigure: () -> Void
    let onPrompt: (String) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                Spacer(minLength: 94)

                ZStack {
                    Circle()
                        .fill(FamiliarTheme.brandGlow)
                        .frame(width: 76, height: 76)
                    Image(systemName: "sparkles")
                        .font(.system(size: 29, weight: .medium))
                        .foregroundStyle(FamiliarTheme.accent)
                }

                VStack(spacing: 8) {
                    Text(String(localized: "empty.title"))
                        .font(.title2.bold())
                    Text(String(localized: "empty.subtitle"))
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                if isProviderConfigured {
                    VStack(spacing: 10) {
                        PromptSuggestion(title: String(localized: "empty.prompt.explain"), onSelect: onPrompt)
                        PromptSuggestion(title: String(localized: "empty.prompt.plan"), onSelect: onPrompt)
                        PromptSuggestion(title: String(localized: "empty.prompt.write"), onSelect: onPrompt)
                    }
                    .frame(maxWidth: 420)
                } else {
                    Button {
                        onConfigure()
                    } label: {
                        Text(String(localized: "empty.configure"))
                            .font(.headline)
                            .padding(.horizontal, 20)
                            .frame(height: 48)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .background(FamiliarTheme.accent, in: Capsule())
                }

                Spacer(minLength: 40)
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
    }
}

private struct PromptSuggestion: View {
    let title: String
    let onSelect: (String) -> Void

    var body: some View {
        Button {
            onSelect(title)
        } label: {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .multilineTextAlignment(.leading)
                Spacer()
                Image(systemName: "arrow.up.left")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(FamiliarTheme.elevatedFill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct FamiliarConversationDrawer: View {
    let conversations: [FamiliarConversation]
    let selectedConversationID: UUID?
    let safeAreaInsets: EdgeInsets
    let onSelect: (FamiliarConversation) -> Void
    let onRename: (FamiliarConversation) -> Void
    let onDelete: (FamiliarConversation) -> Void

    @State private var isSearchPresented = false

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 3) {
                    if conversations.isEmpty {
                        Text(String(localized: "drawer.no_conversations"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 20)
                            .padding(.top, 24)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text(String(localized: "drawer.recent"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 20)
                            .padding(.top, 4)
                            .padding(.bottom, 4)

                        ForEach(conversations) { conversation in
                            conversationRow(conversation)
                        }
                    }
                }
                .padding(.top, drawerHeaderHeight + 8)
                .padding(.bottom, 12)
            }
            .scrollDismissesKeyboard(.interactively)

            drawerHeader
        }
        .background(FamiliarTheme.drawerFill)
        .sheet(isPresented: $isSearchPresented) {
            FamiliarConversationSearchView(
                conversations: conversations,
                selectedConversationID: selectedConversationID,
                onSelect: { conversation in
                    isSearchPresented = false
                    onSelect(conversation)
                }
            )
        }
    }

    private func conversationRow(_ conversation: FamiliarConversation) -> some View {
        Button {
            onSelect(conversation)
        } label: {
            HStack(spacing: 10) {
                Text(conversation.title)
                    .font(.body)
                    .lineLimit(1)
                Spacer(minLength: 4)
            }
            .padding(.horizontal, 14)
            .frame(height: 46)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(conversation.id == selectedConversationID ? .isSelected : [])
        .background(
            conversation.id == selectedConversationID
                ? Color.primary.opacity(0.075)
                : .clear,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .padding(.horizontal, 10)
        .contextMenu {
            Button {
                onRename(conversation)
            } label: {
                Label(String(localized: "conversation.rename"), systemImage: "pencil")
            }
            Button(role: .destructive) {
                onDelete(conversation)
            } label: {
                Label(String(localized: "common.delete"), systemImage: "trash")
            }
        }
    }

    private var drawerHeader: some View {
        HStack {
            Text(String(localized: "app.name"))
                .font(.title2.bold())
            Spacer()
            Button {
                isSearchPresented = true
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .familiarGlassCircle(interactive: true)
            .accessibilityLabel(String(localized: "drawer.search"))
        }
        .padding(.horizontal, 20)
        .padding(.top, safeAreaInsets.top + 10)
        .padding(.bottom, 12)
        .background(alignment: .top) {
            LinearGradient(
                stops: [
                    .init(color: Color(uiColor: .secondarySystemBackground).opacity(0.9), location: 0),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: safeAreaInsets.top + 56)
        }
    }

    private var drawerHeaderHeight: CGFloat {
        safeAreaInsets.top + 66
    }
}

private struct FamiliarConversationSearchView: View {
    @Environment(\.dismiss) private var dismiss

    let conversations: [FamiliarConversation]
    let selectedConversationID: UUID?
    let onSelect: (FamiliarConversation) -> Void

    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool

    private var filteredConversations: [FamiliarConversation] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return conversations }
        return conversations.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            List {
                if filteredConversations.isEmpty {
                    Text(searchText.isEmpty
                         ? String(localized: "drawer.no_conversations")
                         : String(localized: "drawer.no_results"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(filteredConversations) { conversation in
                        Button {
                            onSelect(conversation)
                        } label: {
                            HStack(spacing: 10) {
                                Text(conversation.title)
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Spacer(minLength: 4)
                                if conversation.id == selectedConversationID {
                                    Image(systemName: "checkmark")
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(FamiliarTheme.accent)
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
            .navigationTitle(String(localized: "drawer.search"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.cancel")) { dismiss() }
                }
            }
        }
        .tint(FamiliarTheme.accent)
    }
}
