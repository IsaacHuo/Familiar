import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct FamiliarDraftImage: Identifiable {
    let id: UUID
    let image: UIImage?
    let attachment: FamiliarAttachmentDraft?

    init(id: UUID = UUID(), image: UIImage? = nil, attachment: FamiliarAttachmentDraft? = nil) {
        self.id = id
        self.image = image
        self.attachment = attachment
    }
}

private nonisolated enum FamiliarComposerMode: Equatable {
    case compact
    case fullscreen
}

private enum FamiliarComposerAddDestination {
    case camera
    case photos
    case files
}

struct FamiliarSkillMenuItem: Identifiable, Equatable {
    let id: UUID
    let stableID: String
    let name: String
    let detail: String
}



private struct FamiliarInlinePhotoPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var pending: [PhotosPickerItem]
    let limit: Int
    let onCommit: ([PhotosPickerItem]) -> Void
    let onAllPhotos: ([PhotosPickerItem]) -> Void

    init(selection: [PhotosPickerItem], limit: Int, onCommit: @escaping ([PhotosPickerItem]) -> Void, onAllPhotos: @escaping ([PhotosPickerItem]) -> Void) {
        _pending = State(initialValue: selection)
        self.limit = limit
        self.onCommit = onCommit
        self.onAllPhotos = onAllPhotos
    }

    var body: some View {
        PhotosPicker(selection: $pending, maxSelectionCount: limit, selectionBehavior: .continuousAndOrdered, matching: .images) {
            Text(String(localized: "attachment.choose_photos"))
        }
        .photosPickerStyle(.inline)
        .photosPickerDisabledCapabilities(.selectionActions)
        .photosPickerAccessoryVisibility(.hidden, edges: .all)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .frame(
                            width: FamiliarControlSize.minimumHitTarget,
                            height: FamiliarControlSize.minimumHitTarget
                        )
                }
                .familiarGlassCircle(interactive: true)
                .accessibilityLabel(String(localized: "attachment.close_photos"))
                Spacer()
                Button {
                    if pending.isEmpty { onAllPhotos(pending) } else { onCommit(pending) }
                    dismiss()
                } label: {
                    Text(pending.isEmpty ? String(localized: "attachment.all_photos") : String(format: String(localized: "attachment.add_photos_count"), pending.count))
                        .font(FamiliarTypography.secondary.weight(.semibold))
                        .padding(.horizontal, FamiliarSpacing.large)
                        .frame(height: FamiliarControlSize.minimumHitTarget)
                }
                .familiarGlassSurface(interactive: true)
            }
            .padding(.horizontal, FamiliarSpacing.xLarge)
            .padding(.bottom, FamiliarSpacing.xLarge)
        }
    }
}

struct FamiliarComposer: View {
    @Environment(\.familiarReduceMotion) private var reduceMotion
    @Environment(\.familiarComposerActions) private var actions
    private var onPolish: (@MainActor () -> Void)? { actions?.onPolish }
    private var undoRewrite: (@MainActor () -> Void)? { actions?.onUndo }
    @Environment(\.familiarSkillsDismissRevision) private var dismissSkillsRevision
    @Environment(\.familiarExecutionBlocked) private var executionBlocked
    @Binding var selection: FamiliarComposerSelection?
    @State private var savedSelection: FamiliarComposerSelection?
    @State private var savedSelectionText = ""
    @ScaledMetric(relativeTo: .body) private var skillRowHeight: CGFloat = 62
    @Binding var draft: String
    @Binding var images: [FamiliarDraftImage]
    @Binding var documents: [FamiliarAttachmentDraft]
    @Binding var selectedSkillID: UUID?
    let skills: [FamiliarSkillMenuItem]
    let isSending: Bool
    let isListening: Bool
    let draftScopeID: UUID?
    let attachmentOwnerID: UUID?
    let isAttachmentOwnerCurrent: (UUID?) -> Bool
    let focus: Binding<Bool>
    let onSpeech: () -> Void
    let onSend: () -> Void
    let isEditingMessage: Bool
    let isAnsweringClarification: Bool
    let allowsCustomAnswer: Bool

    @Environment(\.familiarSendPresentation) private var sendPresentation
    @State private var inputControl = FamiliarComposerInputControl()
    @State private var mode: FamiliarComposerMode = .compact
    @State private var measuredTextHeight: CGFloat = 0
    @State private var pendingImports: [FamiliarAttachmentImport] = []
    @State private var importTasks: [UUID: Task<Void, Never>] = [:]
    @State private var importTail: Task<Void, Never>?
    @State private var importTailID: UUID?
    @State private var photoSelection: [PhotosPickerItem] = []
    @State private var fullPhotoSelection: [PhotosPickerItem] = []
    @State private var pendingDestination: FamiliarComposerAddDestination?
    @State private var showsCamera = false
    @State private var showsPhotos = false
    @State private var showsFullPhotos = false
    @State private var transitionToFullPhotos = false
    @State private var showsFiles = false
    @State private var showsSkillPalette = false
    @State private var notice: FamiliarComposerNotice?
    @State private var previewImage: FamiliarImageGalleryRequest?
    private let availableHeight: CGFloat
    /// Scales with Dynamic Type. It must be one value shared by the font and the height
    /// math below: scaling the font while measuring against a fixed 20pt would clip the
    /// user's own text at larger sizes.
    @ScaledMetric(relativeTo: .body) private var editorFontSize: CGFloat = 18
    private var lineHeight: CGFloat { UIFont.systemFont(ofSize: editorFontSize).lineHeight }

    init(
        draft: Binding<String>,
        images: Binding<[FamiliarDraftImage]>,
        documents: Binding<[FamiliarAttachmentDraft]>,
        selectedSkillID: Binding<UUID?>,
        skills: [FamiliarSkillMenuItem],
        isSending: Bool,
        isListening: Bool,
        draftScopeID: UUID?,
        focus: Binding<Bool>,
        onSpeech: @escaping () -> Void,
        onSend: @escaping () -> Void,
        availableHeight: CGFloat,
        isAnsweringClarification: Bool = false,
        allowsCustomAnswer: Bool = true,
        selection: Binding<FamiliarComposerSelection?> = .constant(nil),
        isEditingMessage: Bool = false,
        attachmentOwnerID: UUID? = nil,
        isAttachmentOwnerCurrent: @escaping (UUID?) -> Bool = { _ in true }
    ) {
        self.isEditingMessage = isEditingMessage
        self.attachmentOwnerID = attachmentOwnerID
        self.isAttachmentOwnerCurrent = isAttachmentOwnerCurrent
        _selection = selection
        _draft = draft
        _images = images
        _documents = documents
        _selectedSkillID = selectedSkillID
        self.skills = skills
        self.isSending = isSending
        self.isListening = isListening
        self.draftScopeID = draftScopeID
        self.focus = focus
        self.onSpeech = onSpeech
        self.onSend = onSend
        self.availableHeight = availableHeight
        self.isAnsweringClarification = isAnsweringClarification
        self.allowsCustomAnswer = allowsCustomAnswer
    }

    private var imageSlots: Int { max(0, 4 - images.count - pendingImports.filter { $0.source.isImage }.count) }
    private var documentSlots: Int { max(0, 3 - documents.count - pendingImports.filter { !$0.source.isImage }.count) }
    private var removeGalleryImage: ((UUID) -> Void)? {
        guard !(isEditingMessage && isSending) else { return nil }
        return { id in images.removeAll { $0.id == id } }
    }
    private var isImporting: Bool { pendingImports.contains { $0.phase == .preparing } }
    private var hasText: Bool { !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var canSend: Bool {
        if isAnsweringClarification { return allowsCustomAnswer && hasText }
        return isSending || (pendingImports.isEmpty && (hasText || !documents.isEmpty || !images.isEmpty))
    }
    private var showsStop: Bool { isSending && !isAnsweringClarification }
    private var hasDraftContent: Bool { selectedSkill != nil || !images.isEmpty || !documents.isEmpty || !pendingImports.isEmpty }
    private var effectiveTextHeight: CGFloat { max(measuredTextHeight, CGFloat(max(draft.components(separatedBy: "\n").count, 1)) * lineHeight) }
    private var isLongText: Bool { effectiveTextHeight >= lineHeight * 4 - 0.5 }
    private var showsExpansion: Bool { mode == .fullscreen || isLongText }
    private var compactHeight: CGFloat { max(44, lineHeight + 16) }
    private var editorHeight: CGFloat { min(max(effectiveTextHeight + 16, compactHeight), lineHeight * 6 + 16) }
    private var fieldHeight: CGFloat { mode == .fullscreen ? max(fullscreenHeight - 30, 100) : editorHeight }
    private var fullscreenHeight: CGFloat {
        min(max(availableHeight * 0.8 - 14, 240), max(availableHeight - 14, 240))
    }

    var body: some View {
        GlassEffectContainer(spacing: FamiliarSpacing.small) {
            VStack(spacing: FamiliarSpacing.small) {
                if !isAnsweringClarification {
                    skillPalette
                    draftPreview.background(FamiliarComposerAttachmentAnchor(control: inputControl))
                    if let undoRewrite {
                        Button(action: undoRewrite) { Label(String(localized: "rewrite.undo"), systemImage: "arrow.uturn.backward") }
                            .font(.caption).frame(minHeight: 44)
                            .accessibilityIdentifier("composer.undoPolish")
                    }
                }
                HStack(alignment: .bottom, spacing: FamiliarSpacing.small) {
                    if !isAnsweringClarification {
                        skillMenuButton
                        VStack(spacing: 0) {
                            if hasText, onPolish != nil { polishButton.transition(.scale(scale: 0.01, anchor: .bottom).combined(with: .opacity)) }
                            addButton.frame(height: compactHeight)
                        }.familiarGlassSurface(interactive: true)
                    }
                    HStack(alignment: .bottom, spacing: 0) {
                        editor.frame(height: fieldHeight).clipped()
                        ZStack(alignment: .topLeading) {
                            HStack(spacing: 0) {
                                primaryActionButton.frame(height: compactHeight)
                            }
                            .frame(height: fieldHeight, alignment: .bottom)
                            if showsExpansion { expansionButton }
                        }
                    }
                    // Input controls own their gestures; glass is only the background.
                    .familiarGlassSurface(cornerRadius: FamiliarRadius.overlay)
                }
            }
        }
        .animation(reduceMotion ? nil : FamiliarTelegramMotion.panel, value: hasText)
        .padding(.horizontal, FamiliarSpacing.medium)
        .padding(.vertical, FamiliarSpacing.small)
        .photosPicker(isPresented: $showsFullPhotos, selection: $fullPhotoSelection, maxSelectionCount: max(imageSlots, 1), matching: .images)
        .onChange(of: fullPhotoSelection) { _, items in
            guard !transitionToFullPhotos else { return }
            beginLoadingImages(items)
        }
        .sheet(isPresented: $showsPhotos, onDismiss: showFullPhotosIfNeeded) {
            FamiliarInlinePhotoPickerSheet(selection: photoSelection, limit: max(imageSlots, 1), onCommit: beginLoadingImages, onAllPhotos: { items in transitionToFullPhotos = true; fullPhotoSelection = items })
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showsCamera) {
            FamiliarCameraView { image in
                beginAddingCameraImage(image)
            }
            .presentationDetents([.fraction(0.62)])
            .presentationBackground(.black)
        }
        .fullScreenCover(item: $previewImage) { item in
            FamiliarImageGalleryView(request: item, onRemove: removeGalleryImage)

        }
        .fileImporter(isPresented: $showsFiles, allowedContentTypes: Self.allowedFileTypes, allowsMultipleSelection: true, onCompletion: importFiles)
        .alert(item: $notice) { notice in
            Alert(title: Text(notice.title), message: Text(notice.message), dismissButton: .default(Text(String(localized: "common.ok"))))
        }
        .onChange(of: showsSkillPalette) { _, value in actions?.onSkillsChanged(value) }
        .onChange(of: dismissSkillsRevision) { _, _ in showsSkillPalette = false }
        .onChange(of: focus.wrappedValue) { _, focused in
            if focused { showsSkillPalette = false }
        }
        .onChange(of: isAnsweringClarification) { _, _ in
            measuredTextHeight = 0
            mode = .compact
            showsSkillPalette = false
        }
        .onChange(of: draftScopeID) { _, _ in cancelDraftTasks() }
        .onChange(of: attachmentOwnerID) { _, _ in cancelDraftTasks() }
        .onDisappear { cancelDraftTasks() }
        .animation(reduceMotion ? nil : FamiliarMotion.standard, value: images.map(\.id))
        .animation(reduceMotion ? nil : FamiliarMotion.standard, value: documents.map(\.id))
        .animation(reduceMotion ? nil : FamiliarMotion.standard, value: pendingImports.map(\.phase))
    }

    @ViewBuilder
    private var skillPalette: some View {
        if showsSkills {
            Group {
                if skills.isEmpty {
                    HStack(spacing: FamiliarSpacing.medium) {
                        Image(systemName: "wand.and.stars")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: FamiliarSpacing.xSmall) {
                            Text(String(localized: "slash.empty", defaultValue: "No Skills Available"))
                                .font(FamiliarTypography.sectionTitle)
                            Button(String(localized: "slash.empty.detail")) { actions?.onOpenSkills() }
                                .font(FamiliarTypography.caption).frame(minHeight: 44)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, FamiliarSpacing.large)
                    .frame(minHeight: skillRowHeight)
                } else {
                    ScrollView(.vertical) {
                        LazyVStack(spacing: 0) {
                            ForEach(skills) { skill in
                                Button {
                                    selectedSkillID = skill.id
                                    restoreEditorFocus()
                                    showsSkillPalette = false
                                } label: {
                                    HStack(spacing: FamiliarSpacing.medium) {
                                        Image(systemName: "wand.and.stars")
                                            .frame(width: 24)
                                            .foregroundStyle(.secondary)
                                        VStack(alignment: .leading, spacing: FamiliarSpacing.xSmall) {
                                            Text(skill.name)
                                                .font(FamiliarTypography.sectionTitle)
                                                .foregroundStyle(.primary)
                                            Text(skill.detail.isEmpty ? skill.name : skill.detail)
                                                .font(FamiliarTypography.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                        Spacer()
                                    }
                                    .padding(.horizontal, FamiliarSpacing.large)
                                    .frame(minHeight: skillRowHeight)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(skill.name + ", " + skill.detail)
                                .accessibilityIdentifier("composer.skill." + skill.stableID)
                                if skill.id != skills.last?.id {
                                    Divider().padding(.leading, FamiliarControlSize.minimumHitTarget + FamiliarSpacing.small)
                                }
                            }
                        }
                    }
                    .frame(height: min(CGFloat(skills.count) * skillRowHeight, max(skillRowHeight, availableHeight * 0.45)))
                }
            }
            .familiarGlassSurface(cornerRadius: FamiliarRadius.card)
            .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            .accessibilityElement(children: .contain)
            .accessibilityLabel(String(localized: "slash.palette", defaultValue: "Skills"))
            .accessibilityAction(.escape) { showsSkillPalette = false }
            .accessibilityIdentifier("composer.skillMenu")
        }
    }

    private var showsSkills: Bool { showsSkillPalette && !isSending }

    private var selectedSkill: FamiliarSkillMenuItem? {
        skills.first { $0.id == selectedSkillID }
    }

    private var editor: some View {
        FamiliarComposerTextView(text: $draft, selection: $selection,
            focused: focus, fontSize: editorFontSize,
            placeholder: String(localized: isAnsweringClarification ? "clarification.custom" : "composer.placeholder"),
            editable: (!isAnsweringClarification || allowsCustomAnswer) && !(isEditingMessage && isSending),
            centersSingleLine: mode != .fullscreen, trailingInset: 0,
            onHeight: { height in
                guard abs(measuredTextHeight - height) > 0.5 else { return }
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { measuredTextHeight = height }
            }, inputControl: inputControl)
    }

    private var expansionButton: some View {
        Button { toggleFullscreen() } label: {
            Image(systemName: mode == .fullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                .foregroundStyle(.secondary).frame(width: 44, height: 44)
        }
        .buttonStyle(FamiliarIconButtonStyle())
        .accessibilityLabel(String(localized: mode == .fullscreen ? "composer.collapse" : "composer.expand"))
    }

    private var addButton: some View {
        Menu {
            Button { choose(.camera) } label: { Label(String(localized: "attachment.camera"), systemImage: "camera") }.disabled(imageSlots == 0)
            Button { choose(.photos) } label: { Label(String(localized: "attachment.photos"), systemImage: "photo") }.disabled(imageSlots == 0)
            Button { choose(.files) } label: { Label(String(localized: "attachment.files"), systemImage: "paperclip") }.disabled(documentSlots == 0)
        } label: {
            Image(systemName: "paperclip")
                .font(.system(size: FamiliarIconSize.prominent))
                .frame(
                    width: FamiliarControlSize.minimumHitTarget,
                    height: FamiliarControlSize.minimumHitTarget
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(FamiliarIconButtonStyle())
        .disabled(isEditingMessage && isSending)
        .accessibilityLabel(String(localized: "attachment.add"))
    }

    private var skillMenuButton: some View {
        Button {
            if showsSkillPalette { showsSkillPalette = false }
            else {
                inputControl.commitText()
                savedSelection = selection ?? .caretAtEnd(of: draft)
                savedSelectionText = draft
                focus.wrappedValue = false
                withAnimation(reduceMotion ? nil : FamiliarMotion.interactiveSpring) { showsSkillPalette = true }
            }
        } label: {
            Image(systemName: showsSkillPalette ? "xmark" : "line.3.horizontal")
                .font(.system(size: FamiliarIconSize.prominent))
                .contentTransition(reduceMotion ? .opacity : .symbolEffect(.replace))
                .frame(width: 44, height: compactHeight)
        }
        .buttonStyle(.plain)
        .familiarGlassSurface(interactive: true)
        .disabled(isSending)
        .accessibilityLabel(String(localized: showsSkillPalette ? "skills.close" : "slash.open"))
        .accessibilityIdentifier("composer.skills")
    }

    @ViewBuilder private var polishButton: some View {
        if onPolish != nil {
            Button { inputControl.commitText(); showsSkillPalette = false; focus.wrappedValue = false; onPolish?() } label: {
                Image(systemName: "wand.and.stars").font(.system(size: 20))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain).disabled(isSending || executionBlocked || !hasText)
            .accessibilityLabel(String(localized: "rewrite.title"))
            .accessibilityIdentifier("composer.polish")
        }
    }

    private func restoreEditorFocus() {
        selection = savedSelectionText == draft ? savedSelection?.normalized(in: draft) : .caretAtEnd(of: draft)
        Task { @MainActor in await Task.yield(); focus.wrappedValue = true }
    }

    private var showsSpeechAction: Bool {
        !isAnsweringClarification && !isSending &&
            (isListening || (!hasText && images.isEmpty && documents.isEmpty))
    }

    private var primaryActionSymbol: String {
        showsSpeechAction ? (isListening ? "waveform" : "mic") : (showsStop ? "stop.fill" : "arrow.up")
    }

    /// A single Button retains its identity, frame and accessibility focus while
    /// microphone / send / stop change. Dictation keeps its Stop action as text arrives.
    private var primaryActionButton: some View {
        Button {
            if showsSpeechAction { onSpeech() }
            else if isAnsweringClarification { if canSend { inputControl.commitText(); onSend() } }
            else if isSending { FamiliarHaptics.shared.perform(.selection); onSend() }
            else if !pendingImports.isEmpty { return }
            else if hasText || !documents.isEmpty || !images.isEmpty {
                inputControl.commitText()
                sendPresentation?.capture(view: hasText ? inputControl.view : inputControl.attachmentView, text: draft, scopeID: draftScopeID)
                onSend()
            }
        } label: {
            Image(systemName: primaryActionSymbol)
                .contentTransition(reduceMotion ? .opacity : .symbolEffect(.replace))
                .symbolEffect(.breathe, isActive: showsSpeechAction && isListening && !reduceMotion)
                .font(.system(size: showsSpeechAction ? FamiliarIconSize.prominent : FamiliarIconSize.standard,
                    weight: showsSpeechAction && !isListening ? .regular : .semibold))
                .foregroundStyle(showsSpeechAction ? (isListening ? FamiliarTheme.accent : Color.primary) : FamiliarTheme.onAccent)
                .frame(width: FamiliarControlSize.standardVisual, height: FamiliarControlSize.standardVisual)
                .background(showsSpeechAction ? Color.clear : (canSend ? FamiliarTheme.accent : Color.secondary.opacity(0.28)), in: Circle())
                .frame(width: FamiliarControlSize.minimumHitTarget, height: FamiliarControlSize.minimumHitTarget)
        }
        .buttonStyle(FamiliarIconButtonStyle())
        .disabled(!showsSpeechAction && (!canSend || (!isSending && executionBlocked)))
        .animation(reduceMotion ? nil : FamiliarMotion.micro, value: primaryActionSymbol)
        .animation(reduceMotion ? nil : FamiliarMotion.micro, value: canSend)
        .accessibilityIdentifier(showsSpeechAction ? "composer.speech" : "composer.send")
        .accessibilityLabel(primaryActionLabel)
        .accessibilityHint(showsSpeechAction ? "" : sendDisabledReason ?? "")
    }

    private var primaryActionLabel: String {
        if showsSpeechAction { return String(localized: isListening ? "speech.stop" : "speech.start") }
        return String(localized: isAnsweringClarification ? "clarification.submit" :
            (showsStop ? "message.stop" : (isEditingMessage ? "message.edit.send" : "message.send")))
    }

    private var sendDisabledReason: String? {
        if isSending { return nil }
        if isImporting { return String(localized: "composer.disabled.importing") }
        if !pendingImports.isEmpty { return String(localized: "attachment.resolve_failed") }
        if !hasText && documents.isEmpty && images.isEmpty { return String(localized: "composer.disabled.empty") }
        return nil
    }

    @ViewBuilder private var draftPreview: some View {
        if hasDraftContent {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: FamiliarSpacing.small) {
                    if let selectedSkill {
                        HStack(spacing: FamiliarSpacing.small) {
                            Image(systemName: "wand.and.stars")
                                .foregroundStyle(FamiliarTheme.accent)
                            Text(selectedSkill.name)
                                .font(FamiliarTypography.caption.weight(.semibold))
                                .lineLimit(1)
                            removeButton(label: String(localized: "slash.remove", defaultValue: "Remove Skill")) {
                                selectedSkillID = nil
                            }
                        }
                        .padding(.leading, FamiliarSpacing.medium)
                        .frame(height: 48)
                        .background(FamiliarTheme.elevatedFill, in: Capsule())
                    }
                    ForEach(images) { item in
                        ZStack(alignment: .topTrailing) {
                            Button {
                                openImage(item.id)
                            } label: {
                                Group {
                                    if let attachment = item.attachment {
                                        FamiliarFileThumbnail(url: FamiliarAttachmentStore.url(for: attachment.relativePath), identity: item.id.uuidString, symbol: "photo.badge.exclamationmark", side: 96)
                                    } else if let image = item.image { Image(uiImage: image).resizable().scaledToFill().frame(width: 96, height: 96).clipped() }
                                    else { Image(systemName: "photo.badge.exclamationmark").frame(width: 96, height: 96) }
                                }
                                .clipShape(RoundedRectangle(cornerRadius: FamiliarRadius.card, style: .continuous))
                                .background(FamiliarImageSourceAnchor(id: item.id))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(String(localized: "attachment.preview_image", defaultValue: "Preview image"))

                            Button(role: .destructive) {
                                images.removeAll { $0.id == item.id }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(FamiliarTypography.caption.bold())
                                    .foregroundStyle(.primary)
                                    .frame(width: 28, height: 28)
                                    .background(.regularMaterial, in: Circle())
                                    .frame(width: FamiliarControlSize.minimumHitTarget, height: FamiliarControlSize.minimumHitTarget)
                            }
                            .buttonStyle(.plain)
                            .frame(minWidth: FamiliarControlSize.minimumHitTarget, minHeight: FamiliarControlSize.minimumHitTarget)
                            .disabled(isEditingMessage && isSending)
                            .accessibilityLabel(String(localized: "attachment.remove_image"))
                            .offset(x: 2, y: -2)
                        }
                        .padding(.trailing, FamiliarSpacing.xSmall)
                        .transition(reduceMotion ? .opacity : FamiliarMotion.softRise)
                    }
                    ForEach(documents) { file in
                        HStack(spacing: FamiliarSpacing.small) {
                            FamiliarFileLabel(file: .init(draft: file), compact: true)
                            removeButton(label: String(localized: "attachment.remove_file")) {
                                documents.removeAll { $0.id == file.id }
                            }
                        }
                        .padding(.leading, FamiliarSpacing.medium)
                        .frame(height: 48)
                        .background(FamiliarTheme.elevatedFill, in: Capsule())
                        .transition(reduceMotion ? .opacity : FamiliarMotion.softRise)
                    }
                    ForEach(pendingImports) { item in
                        HStack(spacing: 8) {
                            if item.phase == .preparing { ProgressView().controlSize(.small) }
                            else { Image(systemName: "exclamationmark.circle").foregroundStyle(FamiliarTheme.failure) }
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.source.name).font(.caption.weight(.medium)).lineLimit(1)
                                switch item.phase {
                                case .preparing: Text(String(localized: "attachment.processing")).font(.caption2).foregroundStyle(.secondary)
                                case .failed(let error): Text(error).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                                }
                            }.frame(maxWidth: 180, alignment: .leading)
                            if case .failed = item.phase {
                                Button(String(localized: "attachment.retry")) { startImport(item.id) }
                                    .font(.caption).frame(minHeight: 44)
                            }
                            removeButton(label: String(localized: "attachment.import_cancel")) { cancelImport(item.id) }
                        }
                        .padding(.leading, 12).frame(minHeight: 56)
                        .background(FamiliarTheme.elevatedFill, in: RoundedRectangle(cornerRadius: FamiliarRadius.card))
                        .accessibilityIdentifier("attachment.import." + item.id.uuidString)
                    }
                }
            }
        }
    }

    private func removeButton(label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: "xmark.circle.fill").symbolRenderingMode(.palette).foregroundStyle(.white, .black.opacity(0.7)) }
            .buttonStyle(FamiliarIconButtonStyle())
            .disabled(isEditingMessage && isSending)
            .accessibilityLabel(label)
    }

    private func choose(_ destination: FamiliarComposerAddDestination) {
        showsSkillPalette = false
        pendingDestination = destination
        Task { @MainActor in
            await Task.yield()
            guard let pendingDestination else { return }
            self.pendingDestination = nil
            switch pendingDestination {
            case .camera: showsCamera = true
            case .photos: showsPhotos = true
            case .files: showsFiles = true
            }
        }
    }

    private func toggleFullscreen() {
        setMode(mode == .fullscreen ? .compact : .fullscreen, emphasized: true)
        Task { @MainActor in await Task.yield(); focus.wrappedValue = true }
    }

    private func setMode(_ newMode: FamiliarComposerMode, emphasized: Bool = false) {
        if reduceMotion {
            mode = newMode
        } else {
            withAnimation(emphasized ? FamiliarMotion.emphasized : FamiliarMotion.standard) {
                mode = newMode
            }
        }
    }

    private func showFullPhotosIfNeeded() {
        guard transitionToFullPhotos else { return }
        transitionToFullPhotos = false
        Task { @MainActor in await Task.yield(); showsFullPhotos = true }
    }

    private func openImage(_ id: UUID) {
        let items = images.compactMap { item -> FamiliarImageGalleryItem? in
            guard let attachment = item.attachment, let url = FamiliarAttachmentStore.url(for: attachment.relativePath) else { return nil }
            return .init(id: item.id, url: url)
        }
        guard items.contains(where: { $0.id == id }) else { notice = .fileImportFailed(String(localized: "attachment.error.source_unavailable")); return }
        FamiliarImagePresentation.update { previewImage = .init(id: id, items: items) }
    }

    private func beginAddingCameraImage(_ image: UIImage) { enqueue(.camera(image)) }

    private func beginLoadingImages(_ items: [PhotosPickerItem]) {
        for item in items { enqueue(.photo(item)) }
        photoSelection = []; fullPhotoSelection = []
    }

    private static let allowedFileTypes: [UTType] = FamiliarAnyDocService.supportedExtensions.sorted().compactMap { UTType(filenameExtension: $0) }

    private func importFiles(_ result: Result<[URL], Error>) {
        do { for url in try result.get() { enqueue(.file(url)) } }
        catch {
            let error = error as NSError
            if error.domain == NSCocoaErrorDomain && error.code == NSUserCancelledError { return }
            notice = .fileImportFailed(error.localizedDescription)
        }
    }

    private func enqueue(_ source: FamiliarAttachmentImportSource) {
        let pending = pendingImports.filter { $0.source.isImage == source.isImage }.count
        guard source.isImage ? images.count + pending < 4 : documents.count + pending < 3 else {
            notice = .fileImportFailed(String(localized: "attachment.import_limit")); return
        }
        let item = FamiliarAttachmentImport(id: UUID(), source: source)
        pendingImports.append(item)
        startImport(item.id)
    }

    private func startImport(_ id: UUID) {
        guard let index = pendingImports.firstIndex(where: { $0.id == id }) else { return }
        importTasks[id]?.cancel()
        let attempt = UUID(), scopeID = draftScopeID, ownerID = attachmentOwnerID, source = pendingImports[index].source
        pendingImports[index].attempt = attempt
        pendingImports[index].phase = .preparing
        let predecessor = importTail
        let importActivity = actions?.onAttachmentImport
        importActivity?(true)
        importTasks[id] = Task { @MainActor in
            var prepared: FamiliarAttachmentDraft?
            defer {
                importActivity?(false)
                if importTailID == attempt { importTail = nil; importTailID = nil }
                if pendingImports.first(where: { $0.id == id })?.attempt == attempt { importTasks.removeValue(forKey: id) }
                if let prepared { FamiliarAttachmentStore.remove(relativePath: prepared.relativePath) }
            }
            do {
                // Keep large Photos transfers and document decoding serial in this
                // composer; queued entries remain cancellable without allocating bytes.
                await predecessor?.value
                try Task.checkCancellation()
                guard isAttachmentOwnerCurrent(ownerID) else { return }
                let attachment = try await source.prepare()
                prepared = attachment
                try Task.checkCancellation()
                guard isAttachmentOwnerCurrent(ownerID), scopeID == draftScopeID, let current = pendingImports.firstIndex(where: { $0.id == id && $0.attempt == attempt }) else { return }
                if source.isImage {
                    guard images.count < 4 else { throw FamiliarAttachmentImportError.limit }
                    images.append(.init(id: attachment.id, attachment: attachment))
                } else {
                    guard documents.count < 3 else { throw FamiliarAttachmentImportError.limit }
                    documents.append(attachment)
                }
                prepared = nil
                pendingImports.remove(at: current)
                importTasks.removeValue(forKey: id)
            } catch is CancellationError { }
            catch {
                guard isAttachmentOwnerCurrent(ownerID), scopeID == draftScopeID, let current = pendingImports.firstIndex(where: { $0.id == id && $0.attempt == attempt }) else { return }
                pendingImports[current].phase = .failed(error.localizedDescription)
            }
        }
        importTail = importTasks[id]; importTailID = attempt
    }

    private func cancelImport(_ id: UUID) {
        importTasks.removeValue(forKey: id)?.cancel()
        pendingImports.removeAll { $0.id == id }
    }

    private func cancelDraftTasks() {
        let tasks = Array(importTasks.values)
        importTasks = [:]; pendingImports = []; importTail = nil; importTailID = nil
        photoSelection = []; fullPhotoSelection = []
        tasks.forEach { $0.cancel() }
    }
}

private struct FamiliarComposerNotice: Identifiable {
    enum Kind { case fileImportFailed(String) }
    let id = UUID()
    let kind: Kind
    var title: String {
        switch kind {
        case .fileImportFailed: return String(localized: "attachment.file_import_failed_title")
        }
    }
    var message: String {
        switch kind {
        case .fileImportFailed(let detail): return detail
        }
    }
    static func fileImportFailed(_ detail: String) -> FamiliarComposerNotice {
        FamiliarComposerNotice(kind: .fileImportFailed(detail))
    }
}
