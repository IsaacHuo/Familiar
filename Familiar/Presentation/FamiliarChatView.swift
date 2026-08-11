import SwiftData
import SwiftUI

struct FamiliarChatView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \FamiliarConversation.updatedAt, order: .reverse)
    private var conversations: [FamiliarConversation]

    @StateObject private var controller = FamiliarChatController()
    @State private var isDrawerOpen = false
    @GestureState private var drawerDrag: CGFloat = 0
    @State private var presentedSheet: FamiliarSheetDestination?
    @State private var renameRequest: FamiliarRenameRequest?
    @State private var pendingMessageOperation: FamiliarPendingMessageOperation?
    @State private var capabilityNotice: FamiliarCapabilityNotice?
    @FocusState private var isComposerFocused: Bool

    var body: some View {
        GeometryReader { geometry in
            let drawerWidth = min(max(geometry.size.width * 0.82, 280), geometry.size.width - 56)
            let visibleDrawerWidth = drawerOffset(width: drawerWidth)
            let drawerProgress = visibleDrawerWidth / max(drawerWidth, 1)

            ZStack(alignment: .leading) {
                FamiliarConversationDrawer(
                    conversations: conversations,
                    selectedConversationID: controller.selectedConversationID,
                    onSelect: { conversation in
                        controller.select(conversation.id, in: modelContext)
                        closeDrawer()
                    },
                    onNewConversation: {
                        _ = controller.createConversation(in: modelContext)
                        closeDrawer()
                        isComposerFocused = true
                    },
                    onRename: { conversation in
                        renameRequest = FamiliarRenameRequest(
                            conversation: conversation,
                            title: conversation.title
                        )
                    },
                    onDelete: { conversation in
                        controller.delete([conversation], in: modelContext)
                    },
                    onSettings: {
                        closeDrawer()
                        presentedSheet = .settings
                    }
                )
                .frame(width: drawerWidth)
                .offset(x: visibleDrawerWidth - drawerWidth)

                mainSurface
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: 30 * drawerProgress,
                            style: .continuous
                        )
                    )
                    .shadow(
                        color: .black.opacity(0.12 * drawerProgress),
                        radius: 24,
                        x: -4,
                        y: 0
                    )
                    .scaleEffect(reduceMotion ? 1 : 1 - (0.022 * drawerProgress), anchor: .trailing)
                    .offset(x: visibleDrawerWidth)
                    .overlay {
                        if visibleDrawerWidth > 1 {
                            Color.black.opacity(0.07 * drawerProgress)
                                .contentShape(Rectangle())
                                .onTapGesture { closeDrawer() }
                                .gesture(drawerGesture(width: drawerWidth))
                        }
                    }

                if !isDrawerOpen {
                    Color.clear
                        .contentShape(Rectangle())
                        .frame(width: 22)
                        .frame(maxHeight: .infinity)
                        .gesture(drawerGesture(width: drawerWidth))
                        .accessibilityHidden(true)
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .animation(reduceMotion ? nil : .smooth(duration: 0.32), value: isDrawerOpen)
        }
        .ignoresSafeArea(.keyboard, edges: isDrawerOpen ? .all : [])
        .sheet(item: $presentedSheet) { destination in
            switch destination {
            case .settings:
                FamiliarSettingsView(initialSettings: controller.settings) {
                    controller.updateSettings($0, in: modelContext)
                }
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
        .alert(item: $capabilityNotice) { notice in
            Alert(
                title: Text(String(localized: "capability.coming_soon.title")),
                message: Text(notice.message),
                dismissButton: .default(Text(String(localized: "common.ok")))
            )
        }
        .alert(String(localized: "app.name"), isPresented: Binding(
            get: { controller.errorMessage != nil },
            set: { if !$0 { controller.errorMessage = nil } }
        )) {
            if !FamiliarKeychainStore.isConfigured(for: controller.settings.providerID) {
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
        }
    }

    @ViewBuilder
    private var mainSurface: some View {
        NavigationStack {
            chatBody
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    FamiliarComposer(
                        draft: $controller.draft,
                        isSending: controller.isSending,
                        focus: $isComposerFocused,
                        onSpeech: { capabilityNotice = .speech },
                        onSend: {
                            if controller.isSending {
                                controller.cancelSending(in: modelContext)
                            } else {
                                controller.startSending(in: modelContext)
                            }
                        }
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
                isProviderConfigured: FamiliarKeychainStore.isConfigured(for: controller.settings.providerID),
                providerTitle: controller.settings.selectedProvider.displayName,
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
                onResolveConfirmation: { request, decision in
                    controller.resolveConfirmation(request, decision: decision)
                },
                onEdit: { pendingMessageOperation = .edit($0) },
                onRetry: { pendingMessageOperation = .retry($0) }
            )
        }
    }

    private var topBar: some View {
        let selectedProvider = controller.settings.selectedProvider
        let providers = selectedProvider.isCustom
            ? FamiliarProviderCatalog.builtIn + [selectedProvider]
            : FamiliarProviderCatalog.builtIn
        return FamiliarChatTopBar(
            provider: selectedProvider,
            model: controller.settings.selectedModel,
            providerOptions: providers,
            isSending: controller.isSending,
            onOpenDrawer: { setDrawerOpen(true) },
            onSelectModel: { providerID, modelID in
                controller.selectModel(providerID: providerID, modelID: modelID, in: modelContext)
            },
            onNewConversation: {
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
        DragGesture(minimumDistance: 8)
            .updating($drawerDrag) { value, state, _ in
                state = value.translation.width
            }
            .onEnded { value in
                let projected = value.predictedEndTranslation.width
                if isDrawerOpen {
                    isDrawerOpen = projected > -(width * 0.28)
                } else {
                    isDrawerOpen = projected > width * 0.22
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
            withAnimation(.smooth(duration: 0.32)) {
                isDrawerOpen = isOpen
            }
        }
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

private enum FamiliarCapabilityNotice: String, Identifiable {
    case attachments
    case speech

    var id: String { rawValue }

    var message: String {
        switch self {
        case .attachments: String(localized: "capability.attachments.detail")
        case .speech: String(localized: "capability.speech.detail")
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
                    .background(.ultraThinMaterial)
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

            Spacer(minLength: 0)

            Menu {
                ForEach(providerOptions) { provider in
                    Menu(provider.displayName) {
                        let models = provider.curatedModels.isEmpty && self.provider.id == provider.id
                            ? [model]
                            : provider.curatedModels
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
}



private struct FamiliarEmptyConversationView: View {
    let isProviderConfigured: Bool
    let providerTitle: String
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
                        Text(String(format: String(localized: "empty.configure"), providerTitle))
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
    let onSelect: (FamiliarConversation) -> Void
    let onNewConversation: () -> Void
    let onRename: (FamiliarConversation) -> Void
    let onDelete: (FamiliarConversation) -> Void
    let onSettings: () -> Void

    @State private var searchText = ""

    private var filteredConversations: [FamiliarConversation] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return conversations }
        return conversations.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(String(localized: "app.name"))
                    .font(.title2.bold())
                Spacer()
                Button(action: onNewConversation) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 42, height: 42)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "conversation.new"))
            }
            .padding(.horizontal, 18)
            .padding(.top, 10)

            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(String(localized: "drawer.search"), text: $searchText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            .padding(.horizontal, 13)
            .frame(height: 42)
            .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 3) {
                    if filteredConversations.isEmpty {
                        Text(searchText.isEmpty ? String(localized: "drawer.no_conversations") : String(localized: "drawer.no_results"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 18)
                            .padding(.top, 24)
                    } else {
                        Text(String(localized: "drawer.recent"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 18)
                            .padding(.top, 4)
                            .padding(.bottom, 6)

                        ForEach(filteredConversations) { conversation in
                            Button {
                                onSelect(conversation)
                            } label: {
                                HStack(spacing: 10) {
                                    Text(conversation.title)
                                        .font(.subheadline)
                                        .lineLimit(1)
                                    Spacer(minLength: 4)
                                }
                                .padding(.horizontal, 13)
                                .frame(height: 44)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .background(
                                conversation.id == selectedConversationID
                                    ? Color.primary.opacity(0.075)
                                    : .clear,
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                            )
                            .padding(.horizontal, 6)
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
                    }
                }
            }

            Divider().opacity(0.6)

            Button(action: onSettings) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(FamiliarTheme.accent.opacity(0.14))
                        Text("F")
                            .font(.subheadline.bold())
                            .foregroundStyle(FamiliarTheme.accent)
                    }
                    .frame(width: 36, height: 36)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "app.name"))
                            .font(.subheadline.weight(.semibold))
                        Text(String(localized: "drawer.settings"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 16)
                .frame(height: 66)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }
}
