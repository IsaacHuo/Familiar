import SwiftData
import SwiftUI

struct FamiliarDraftRewriteUndo {
    let source: String
    let applied: String
    let selection: TextSelection?
}

struct FamiliarDraftRewriteSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var context
    let controller: FamiliarChatController
    private let source: String
    private let sourceID: UUID
    private let sourceSelection: TextSelection?
    private let initialSettings: FamiliarSettings
    @State private var settings: FamiliarSettings
    @State private var tab = Mode.style
    @State private var language = "en"
    @State private var style = "rewrite.style.natural"
    @State private var custom = ""
    @State private var output = ""
    @State private var result: FamiliarDraftRewriteResult?
    @State private var failure: String?
    @State private var task: Task<Void, Never>?
    @State private var requestID: UUID?

    private enum Mode: String, CaseIterable { case translate, style, correct }
    private let styles = ["rewrite.style.natural", "rewrite.style.formal", "rewrite.style.short", "rewrite.style.custom"]

    init(controller: FamiliarChatController, settings: FamiliarSettings) {
        self.controller = controller
        source = controller.draft
        sourceID = controller.selectedConversationID ?? controller.draftConversationID
        sourceSelection = controller.draftSelection
        initialSettings = settings
        _settings = State(initialValue: settings)
    }

    private var operation: FamiliarDraftRewriteOperation {
        switch tab {
        case .translate: return .translate(language: Locale.current.localizedString(forLanguageCode: language) ?? language)
        case .correct: return .correct
        case .style:
            let instruction: String
            switch style {
            case "rewrite.style.formal": instruction = "Use a formal, professional tone."
            case "rewrite.style.short": instruction = "Make it concise, keeping the essential information."
            case "rewrite.style.custom": instruction = custom
            default: instruction = "Make the wording clear and natural, preserving the original language."
            }
            return .style(instruction: instruction)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: FamiliarSpacing.large) {
                    Picker(String(localized: "rewrite.operation"), selection: $tab) {
                        ForEach(Mode.allCases, id: \.self) { mode in Text(String(localized: String.LocalizationValue("rewrite.mode." + mode.rawValue))).tag(mode) }
                    }.pickerStyle(.segmented)
                    if tab == .translate {
                        Picker(String(localized: "rewrite.language"), selection: $language) {
                            ForEach(["zh-Hans", "en", "ja", "ko", "fr", "de", "es"], id: \.self) { code in
                                Text(Locale.current.localizedString(forLanguageCode: code) ?? code).tag(code)
                            }
                        }.pickerStyle(.menu)
                    }
                    if tab == .style {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(styles, id: \.self) { value in
                                    Button { style = value } label: {
                                        Text(String(localized: String.LocalizationValue(value))).font(.subheadline)
                                            .padding(.horizontal, 14).frame(minHeight: 44)
                                            .background(style == value ? FamiliarTheme.accentTint : FamiliarTheme.inset, in: Capsule())
                                    }.buttonStyle(.plain)
                                }
                            }
                        }
                        if style == "rewrite.style.custom" {
                            TextField(String(localized: "rewrite.custom"), text: $custom, axis: .vertical).textFieldStyle(.roundedBorder)
                        }
                    }
                    DisclosureGroup(String(localized: "rewrite.original")) { Text(source).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                    VStack(alignment: .leading, spacing: FamiliarSpacing.medium) {
                        HStack {
                            Text(String(localized: "rewrite.preview")).font(.headline)
                            Spacer()
                            if requestID != nil { ProgressView().controlSize(.small) }
                        }
                        if output.isEmpty { Text(String(localized: "rewrite.preview.empty")).foregroundStyle(.secondary) }
                        else { Text(output).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                        if let failure { Text(failure).font(.subheadline).foregroundStyle(FamiliarTheme.failure) }
                        if let result {
                            Text((FamiliarProviderCatalog.descriptor(for: result.model.providerID)?.displayName ?? result.model.providerID) + " · " + result.model.modelID)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }.padding().frame(maxWidth: .infinity, alignment: .leading)
                        .background(FamiliarTheme.elevatedFill, in: RoundedRectangle(cornerRadius: FamiliarRadius.card))
                    Text(String(localized: "rewrite.provider_note")).font(.caption).foregroundStyle(.secondary)
                }.padding(FamiliarSpacing.large)
            }
            .navigationTitle(String(localized: "rewrite.title")).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(String(localized: "common.cancel")) { cancel(); dismiss() } }
                ToolbarItem(placement: .topBarTrailing) { modelMenu }
            }
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Button(String(localized: requestID == nil ? "rewrite.generate" : "rewrite.stop")) { if requestID == nil { generate() } else { cancel() } }
                        .buttonStyle(.bordered).frame(minHeight: 44)
                        .disabled(requestID == nil && (controller.execution.isBusy || (tab == .style && style == "rewrite.style.custom" && custom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)))
                    Button(String(localized: "rewrite.apply")) { apply() }
                        .buttonStyle(.borderedProminent).frame(maxWidth: .infinity, minHeight: 44)
                        .disabled(result == nil || requestID != nil)
                        .accessibilityIdentifier("rewrite.apply")
                }.padding().background(.bar)
            }
        }
        .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
        .onChange(of: tab) { _, _ in cancel(); result = nil; output = ""; failure = nil }
        .onChange(of: style) { _, _ in cancel(); result = nil; output = ""; failure = nil }
        .onChange(of: language) { _, _ in cancel(); result = nil; output = ""; failure = nil }
        .onChange(of: custom) { _, _ in cancel(); result = nil }
        .onChange(of: scenePhase) { _, phase in if phase != .active { cancel() } }
        .onDisappear { cancel() }
        .accessibilityIdentifier("rewrite.editor")
    }

    private var modelMenu: some View {
        Menu {
            Button(String(localized: "rewrite.model.current")) { cancel(); result = nil; settings = initialSettings }
            ForEach(FamiliarProviderCatalog.builtIn) { provider in
                if FamiliarProviderFactory.credential(for: provider) != nil || FamiliarChatTestScenario.isEnabled {
                    Menu(provider.displayName) {
                        ForEach(provider.curatedModels) { model in
                            Button(model.displayName) {
                                cancel(); result = nil; output = ""
                                settings.providerID = provider.id; settings.modelID = model.id
                            }
                        }
                    }
                }
            }
        } label: {
            Text(settings.selectedModel.displayName).font(.subheadline).lineLimit(1)
        }.accessibilityLabel(String(localized: "rewrite.model"))
    }

    private func generate() {
        failure = nil; output = ""; result = nil
        let id = UUID(), operation = operation, model = FamiliarModelReference(providerID: settings.providerID, modelID: settings.modelID)
        guard controller.execution.claim(id) else { failure = String(localized: "chat.execution.busy"); return }
        requestID = id
        task = Task { @MainActor in
            defer { controller.execution.release(id); if requestID == id { requestID = nil; task = nil } }
            do {
                let provider = try controller.makeDraftRewriteProvider(settings: settings)
                let value = try await FamiliarDraftRewriteService.generate(text: source, operation: operation, model: model,
                    maximumInputCharacters: settings.selectedModel.capabilities.maximumInputCharacters,
                    provider: provider, onText: { text in if requestID == id { output = text } })
                guard !Task.isCancelled, requestID == id else { return }
                result = value
            } catch is CancellationError { return }
            catch { if requestID == id { failure = error.localizedDescription } }
        }
    }

    private func cancel() {
        task?.cancel(); task = nil
        requestID = nil
        result = nil
    }

    private func apply() {
        guard let result, requestID == nil else { return }
        do { try controller.applyDraftRewrite(result, source: source, sourceID: sourceID, selection: sourceSelection) }
        catch { failure = error.localizedDescription; return }
        Task { await controller.checkpointDraft(in: context) }
        dismiss()
    }
}
