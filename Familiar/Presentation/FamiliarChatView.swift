import SwiftData
import SwiftUI

struct FamiliarChatView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FamiliarConversation.updatedAt, order: .reverse)
    private var conversations: [FamiliarConversation]

    @StateObject private var controller = FamiliarChatController()
    @State private var showingSettings = false

    var body: some View {
        NavigationSplitView {
            conversationList
        } detail: {
            chatDetail
        }
        .sheet(isPresented: $showingSettings) {
            FamiliarSettingsView(initialSettings: controller.settings) {
                controller.updateSettings($0)
            }
        }
        .alert("Familiar", isPresented: Binding(
            get: { controller.errorMessage != nil },
            set: { if !$0 { controller.errorMessage = nil } }
        )) {
            if !FamiliarKeychainStore.isConfigured {
                Button("打开设置") { showingSettings = true }
            }
            Button("知道了", role: .cancel) {}
        } message: {
            Text(controller.errorMessage ?? "未知错误")
        }
        .onAppear {
            if controller.selectedConversationID == nil,
               let first = conversations.first {
                controller.select(first.id, in: modelContext)
            }
        }
    }

    private var conversationList: some View {
        List(selection: Binding(
            get: { controller.selectedConversationID },
            set: { controller.select($0, in: modelContext) }
        )) {
            ForEach(conversations) { conversation in
                VStack(alignment: .leading, spacing: 4) {
                    Text(conversation.title)
                        .font(.headline)
                        .lineLimit(2)
                    Text(conversation.updatedAt, format: .relative(presentation: .named))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .tag(conversation.id)
                .contextMenu {
                    Button("删除", role: .destructive) {
                        controller.delete([conversation], in: modelContext)
                    }
                }
            }
            .onDelete { offsets in
                controller.delete(offsets.map { conversations[$0] }, in: modelContext)
            }
        }
        .navigationTitle("Familiar")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showingSettings = true
                } label: {
                    Label("设置", systemImage: "gearshape")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    _ = controller.createConversation(in: modelContext)
                } label: {
                    Label("新对话", systemImage: "square.and.pencil")
                }
                .disabled(controller.isSending)
            }
        }
    }

    private var chatDetail: some View {
        VStack(spacing: 0) {
            if controller.messages.isEmpty && controller.streamingText.isEmpty {
                ContentUnavailableView {
                    Label("开始对话", systemImage: "bubble.left.and.bubble.right")
                } description: {
                    Text("Familiar 目前只进行聊天问答，不读取任何账号或教务信息。")
                } actions: {
                    Button("配置 DeepSeek") { showingSettings = true }
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                messageTimeline
            }
            composer
        }
        .navigationTitle(selectedTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Text(controller.settings.model.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var selectedTitle: String {
        conversations.first(where: { $0.id == controller.selectedConversationID })?.title ?? "新对话"
    }

    private var messageTimeline: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: AppSpacing.card) {
                    ForEach(controller.messages) { message in
                        FamiliarMessageRow(message: message)
                            .id(message.id)
                    }
                    if !controller.streamingText.isEmpty {
                        FamiliarStreamingRow(content: controller.streamingText)
                            .id("streaming")
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(AppSpacing.page)
                .frame(maxWidth: 820)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: controller.messages.count) { _, _ in
                withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onChange(of: controller.streamingText) { _, _ in
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: AppSpacing.standard) {
            TextField("问 Familiar…", text: $controller.draft, axis: .vertical)
                .lineLimit(1...6)
                .textFieldStyle(.plain)
                .submitLabel(.send)
                .onSubmit {
                    if !controller.draft.contains("\n") {
                        controller.startSending(in: modelContext)
                    }
                }

            Button {
                if controller.isSending {
                    controller.cancelSending()
                } else {
                    controller.startSending(in: modelContext)
                }
            } label: {
                Image(systemName: controller.isSending ? "stop.fill" : "arrow.up")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(FamiliarTheme.accent, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(controller.isSending ? "停止回答" : "发送")
            .disabled(!controller.isSending && controller.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, AppSpacing.card)
        .padding(.vertical, AppSpacing.standard)
        .familiarGlassSurface(interactive: true)
        .padding(.horizontal, AppSpacing.card)
        .padding(.vertical, AppSpacing.compact)
    }
}

private struct FamiliarMessageRow: View {
    let message: FamiliarMessageSnapshot

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 48) }
            Group {
                if message.role == .assistant {
                    FamiliarMarkdownWebView(markdown: message.content)
                } else {
                    Text(message.content)
                        .textSelection(.enabled)
                }
            }
            .padding(AppSpacing.card)
            .background(
                message.role == .user ? FamiliarTheme.userFill : FamiliarTheme.assistantFill,
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            if message.role == .assistant { Spacer(minLength: 48) }
        }
    }
}

private struct FamiliarStreamingRow: View {
    let content: String

    var body: some View {
        HStack(alignment: .bottom) {
            Text(content)
                .textSelection(.enabled)
                .padding(AppSpacing.card)
                .background(FamiliarTheme.assistantFill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            ProgressView()
                .controlSize(.small)
            Spacer(minLength: 48)
        }
    }
}
