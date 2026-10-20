import SwiftData
import SwiftUI
import UIKit

struct FamiliarDraftRewriteUndo {
    let source: String
    let applied: String
    let selection: FamiliarComposerSelection?
}

struct FamiliarDraftRewriteSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var context
    let controller: FamiliarChatController
    private let source: String
    private let sourceID: UUID
    private let sourceRevision: UUID
    private let sourceSelection: FamiliarComposerSelection?
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
    @State private var showsOriginal = false
    @State private var detent = PresentationDetent.medium
    @State private var detentBeforeKeyboard = PresentationDetent.medium
    @Namespace private var modeSelection
    @Namespace private var styleSelection
    @Environment(\.familiarReduceMotion) private var reduceMotion
    @FocusState private var customFocused: Bool
    @Environment(\.dynamicTypeSize) private var typeSize

    private enum Mode: String, CaseIterable { case translate, style, correct }
    private let styles = ["rewrite.style.natural", "rewrite.style.formal", "rewrite.style.short", "rewrite.style.custom"]

    init(controller: FamiliarChatController, settings: FamiliarSettings) {
        self.controller = controller
        source = controller.draft
        sourceRevision = controller.draftRevision
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
        VStack(spacing: 20) {
            HStack {
                Button { cancel(); dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 22)).frame(width: 44, height: 44)
                }.buttonStyle(.plain).familiarGlassCircle(interactive: true)
                    .accessibilityLabel(String(localized: "common.cancel"))
                Spacer()
                Text(String(localized: "rewrite.title")).font(.headline)
                Spacer()
                modelMenu
            }
            .padding(.top, 14)

            modePicker

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    options
                    HStack {
                        Text(String(localized: output.isEmpty || showsOriginal ? "rewrite.original" : "rewrite.preview"))
                            .font(.subheadline).foregroundStyle(.secondary)
                        Spacer()
                        if !output.isEmpty {
                            Button { showsOriginal.toggle() } label: {
                                Image(systemName: "arrow.left.arrow.right").frame(width: 44, height: 44)
                            }.buttonStyle(.plain).accessibilityLabel(String(localized: "rewrite.compare"))
                        }
                        if requestID != nil { ProgressView().controlSize(.small) }
                    }
                    Text(output.isEmpty || showsOriginal ? source : output)
                        .font(.body).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    if let failure { Text(failure).font(.subheadline).foregroundStyle(FamiliarTheme.failure) }
                    HStack {
                        Spacer()
                        Button {
                            UIPasteboard.general.string = output.isEmpty || showsOriginal ? source : output
                            FamiliarAccessibility.announce(String(localized: "common.copied"))
                        } label: { Image(systemName: "doc.on.doc").font(.system(size: 22)).frame(width: 44, height: 44) }
                            .buttonStyle(.plain).tint(FamiliarTheme.accent).accessibilityLabel(String(localized: "common.copy"))
                    }
                }
                .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .background(FamiliarTheme.surface, in: RoundedRectangle(cornerRadius: 28))
            }
            .scrollDismissesKeyboard(.interactively)
            .frame(maxHeight: .infinity)

            HStack(spacing: 10) {
                Button {
                    if requestID != nil { cancel() }
                    else if result != nil { apply() }
                    else { showsOriginal = false; generate() }
                } label: {
                    Text(String(localized: requestID != nil ? "rewrite.stop" : result != nil ? "rewrite.apply" : "rewrite.generate"))
                        .font(.headline).frame(maxWidth: .infinity, minHeight: 52)
                        .foregroundStyle(.white).background(FamiliarTheme.accent, in: Capsule())
                }.buttonStyle(.plain)
                    .disabled(requestID == nil && result == nil && generationBlocked)
                    .opacity(requestID == nil && result == nil && generationBlocked ? 0.45 : 1)
                    .accessibilityIdentifier(result == nil ? "rewrite.generate" : "rewrite.apply")
                if result != nil {
                    Button { showsOriginal = false; generate() } label: {
                        Image(systemName: "arrow.clockwise").font(.system(size: 22))
                            .frame(width: 52, height: 52).foregroundStyle(.white)
                            .background(FamiliarTheme.accent, in: Circle())
                    }.buttonStyle(.plain).disabled(controller.execution.isBusy)
                        .accessibilityLabel(String(localized: "rewrite.regenerate"))
                }
            }.padding(.horizontal, 14).padding(.bottom, 12)
        }
        .padding(.horizontal, 16)
        .background(FamiliarTheme.canvas)
        .presentationBackground(FamiliarTheme.canvas)
        .presentationCornerRadius(38)
        .presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.medium, .large], selection: Binding(get: { typeSize.isAccessibilitySize ? .large : detent }, set: { detent = $0 }))
        .presentationDragIndicator(.hidden)
        .onChange(of: tab) { _, _ in cancel(); output = ""; failure = nil; showsOriginal = false }
        .onChange(of: style) { _, _ in cancel(); output = ""; failure = nil; showsOriginal = false }
        .onChange(of: language) { _, _ in cancel(); output = ""; failure = nil; showsOriginal = false }
        .onChange(of: custom) { _, _ in cancel(); output = ""; failure = nil }
        .onChange(of: customFocused) { _, active in
            if active { detentBeforeKeyboard = detent }
            withAnimation(reduceMotion ? nil : FamiliarTelegramMotion.panel) { detent = active || typeSize.isAccessibilitySize ? .large : detentBeforeKeyboard }
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { cancel() } }
        .onDisappear { cancel() }
        .accessibilityIdentifier("rewrite.editor")
    }

    private var modePicker: some View {
        HStack(spacing: 0) {
            ForEach(Mode.allCases, id: \.self) { mode in
                Button { withAnimation(reduceMotion ? nil : FamiliarTelegramMotion.panel) { tab = mode } } label: {
                    VStack(spacing: 5) {
                        Image(systemName: mode == .translate ? "translate" : mode == .style ? "wand.and.stars" : "checkmark.magnifyingglass")
                            .font(.system(size: 24))
                        Text(String(localized: String.LocalizationValue("rewrite.mode." + mode.rawValue))).font(.caption)
                    }.frame(maxWidth: .infinity, minHeight: 58)
                        .background { if tab == mode { Capsule().fill(FamiliarTheme.elevatedFill).matchedGeometryEffect(id: "mode", in: modeSelection) } }
                }.buttonStyle(.plain).accessibilityAddTraits(tab == mode ? .isSelected : [])
            }
        }.padding(3).background(FamiliarTheme.surface, in: Capsule())
            .overlay { Capsule().stroke(FamiliarTheme.separator, lineWidth: 1) }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(String(localized: "rewrite.operation"))
    }

    @ViewBuilder private var options: some View {
        if tab == .style {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(styles, id: \.self) { value in
                        Button { withAnimation(reduceMotion ? nil : FamiliarTelegramMotion.panel) { style = value } } label: {
                            VStack(spacing: 6) {
                                Image(systemName: value == "rewrite.style.custom" ? "text.bubble" : value == "rewrite.style.short" ? "text.alignleft" : value == "rewrite.style.formal" ? "textformat" : "wand.and.stars")
                                    .font(.system(size: 22))
                                Text(String(localized: String.LocalizationValue(value))).font(.caption)
                            }.frame(minWidth: 60, minHeight: 60)
                                .background { if style == value { Capsule().fill(FamiliarTheme.elevatedFill).matchedGeometryEffect(id: "style", in: styleSelection) } }
                        }.buttonStyle(.plain).accessibilityAddTraits(style == value ? .isSelected : [])
                    }
                }
            }
            if style == "rewrite.style.custom" {
                TextField(String(localized: "rewrite.custom"), text: $custom, axis: .vertical).focused($customFocused)
                    .padding(12).background(FamiliarTheme.elevatedFill, in: RoundedRectangle(cornerRadius: 12))
            }
        } else if tab == .translate {
            Picker(String(localized: "rewrite.language"), selection: $language) {
                ForEach(["zh-Hans", "en", "ja", "ko", "fr", "de", "es"], id: \.self) { code in
                    Text(Locale.current.localizedString(forLanguageCode: code) ?? code).tag(code)
                }
            }.pickerStyle(.menu)
        }
    }

    private var generationBlocked: Bool {
        controller.execution.isBusy || (tab == .style && style == "rewrite.style.custom" && custom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private var modelMenu: some View {
        Menu {
            Button(String(localized: "rewrite.model.current")) { cancel(); output = ""; failure = nil; settings = initialSettings }
            ForEach(FamiliarProviderCatalog.builtIn) { provider in
                if FamiliarProviderFactory.credential(for: provider) != nil || FamiliarChatTestScenario.isEnabled {
                    Menu(provider.displayName) {
                        ForEach(provider.curatedModels) { model in
                            Button(model.displayName) {
                                cancel(); output = ""; failure = nil
                                settings.providerID = provider.id; settings.modelID = model.id
                            }
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "cpu").font(.system(size: 22)).frame(width: 44, height: 44)
        }.buttonStyle(.plain).familiarGlassCircle(interactive: true).accessibilityLabel(String(localized: "rewrite.model"))
            .accessibilityValue(settings.selectedProvider.displayName + " · " + settings.selectedModel.displayName)
            .accessibilityHint(String(localized: "rewrite.provider_note"))
    }

    private func generate() {
        failure = nil; output = ""; result = nil
        let id = UUID(), operation = operation, model = FamiliarModelReference(providerID: settings.providerID, modelID: settings.modelID)
        guard controller.execution.claim(id) else { failure = String(localized: "chat.execution.busy"); return }
        requestID = id
        controller.draftRewriteRequestID = id
        task = Task { @MainActor in
            defer {
                controller.execution.release(id)
                if controller.draftRewriteRequestID == id { controller.draftRewriteRequestID = nil }
                if requestID == id { requestID = nil; task = nil }
            }
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
        do { try controller.applyDraftRewrite(result, source: source, sourceID: sourceID, sourceRevision: sourceRevision, selection: sourceSelection) }
        catch { failure = error.localizedDescription; return }
        Task { await controller.checkpointDraft(in: context) }
        dismiss()
    }
}
