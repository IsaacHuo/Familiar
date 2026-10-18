import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct FamiliarDraftImage: Identifiable {
    let id: UUID
    let image: UIImage
    let attachment: FamiliarAttachmentDraft?

    init(id: UUID = UUID(), image: UIImage, attachment: FamiliarAttachmentDraft? = nil) {
        self.id = id
        self.image = image
        self.attachment = attachment
    }
}

private nonisolated enum FamiliarComposerMode: Equatable {
    case compact
    case expanded
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

private struct FamiliarComposerTextHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
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
    @Binding var selection: TextSelection?
    @State private var savedSelection: Range<Int>?
    @ScaledMetric(relativeTo: .body) private var skillRowHeight: CGFloat = 62
    @Binding var draft: String
    @Binding var images: [FamiliarDraftImage]
    @Binding var documents: [FamiliarAttachmentDraft]
    @Binding var selectedSkillID: UUID?
    let skills: [FamiliarSkillMenuItem]
    let isSending: Bool
    let isListening: Bool
    let draftScopeID: UUID?
    let focus: FocusState<Bool>.Binding
    let onSpeech: () -> Void
    let onSend: () -> Void
    let isAnsweringClarification: Bool
    let allowsCustomAnswer: Bool

    @State private var mode: FamiliarComposerMode = .compact
    @State private var measuredTextHeight: CGFloat = 0
    @State private var importingFileCount = 0
    @State private var importTasks: [UUID: Task<Void, Never>] = [:]
    @State private var photoTasks: [UUID: Task<Void, Never>] = [:]
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
    @Namespace private var imageTransition
    @State private var previewImage: FamiliarDraftImage?
    private let availableHeight: CGFloat
    /// Scales with Dynamic Type. It must be one value shared by the font and the height
    /// math below: scaling the font while measuring against a fixed 20pt would clip the
    /// user's own text at larger sizes.
    @ScaledMetric(relativeTo: .body) private var editorFontSize: CGFloat = 18
    private var lineHeight: CGFloat { UIFont.systemFont(ofSize: editorFontSize).lineHeight }
    /// SwiftUI's TextEditor lays its first line out below this inset; the
    /// placeholder mirrors it so both render on the same line.
    private let textEditorTopInset: CGFloat = 8
    /// Centers the compact text block on the control row so its line shares the
    /// add/mic/send center instead of sitting above it.
    private var compactTextTopPadding: CGFloat {
        max((controlsHeight - effectiveTextHeight) / 2 - textEditorTopInset, 0)
    }

    init(
        draft: Binding<String>,
        images: Binding<[FamiliarDraftImage]>,
        documents: Binding<[FamiliarAttachmentDraft]>,
        selectedSkillID: Binding<UUID?>,
        skills: [FamiliarSkillMenuItem],
        isSending: Bool,
        isListening: Bool,
        draftScopeID: UUID?,
        focus: FocusState<Bool>.Binding,
        onSpeech: @escaping () -> Void,
        onSend: @escaping () -> Void,
        availableHeight: CGFloat,
        isAnsweringClarification: Bool = false,
        allowsCustomAnswer: Bool = true,
        selection: Binding<TextSelection?> = .constant(nil)
    ) {
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

    private var isImporting: Bool { importingFileCount > 0 || !photoTasks.isEmpty }
    private var hasText: Bool { !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var canSend: Bool {
        if isAnsweringClarification { return allowsCustomAnswer && hasText }
        return isSending || (!isImporting && (hasText || !documents.isEmpty || !images.isEmpty))
    }
    private var showsStop: Bool { isSending && !isAnsweringClarification }
    private var hasDraftContent: Bool { selectedSkill != nil || !images.isEmpty || !documents.isEmpty || isImporting }
    private var effectiveTextHeight: CGFloat { max(measuredTextHeight, CGFloat(max(draft.components(separatedBy: "\n").count, 1)) * lineHeight) }
    private var isLongText: Bool { effectiveTextHeight >= lineHeight * 4 - 0.5 }
    private var showsExpansion: Bool { mode == .fullscreen || isLongText }
    private var editorHeight: CGFloat { min(max(effectiveTextHeight + 18, 44), lineHeight * 4 + 20) }
    private var controlsHeight: CGFloat { mode == .compact ? max(44, editorHeight) : editorHeight + 8 + 44 }
    private var fullscreenHeight: CGFloat {
        min(max(availableHeight * 0.8 - 14, 240), max(availableHeight - 14, 240))
    }

    var body: some View {
        GlassEffectContainer(spacing: FamiliarSpacing.small) {
            VStack(spacing: FamiliarSpacing.small) {
                if !isAnsweringClarification {
                    skillPalette
                    draftPreview
                    if let undoRewrite {
                        Button(action: undoRewrite) { Label(String(localized: "rewrite.undo"), systemImage: "arrow.uturn.backward") }
                            .font(.caption).frame(minHeight: 44)
                    }
                }
                HStack(alignment: .bottom, spacing: FamiliarSpacing.small) {
                    if !isAnsweringClarification {
                        skillMenuButton
                        VStack(spacing: 2) {
                            if hasText && effectiveTextHeight >= lineHeight * 3 { polishButton }
                            addButton
                        }
                        .familiarGlassSurface(interactive: true)
                    }
                    HStack(alignment: .bottom, spacing: 0) {
                        editor
                            .frame(height: mode == .fullscreen ? max(fullscreenHeight - 30, 100) : editorHeight)
                        if !isAnsweringClarification, hasText, effectiveTextHeight < lineHeight * 3 { polishButton }
                        if !isAnsweringClarification && !hasText && images.isEmpty && documents.isEmpty && !isSending { micButton }
                        else { sendButton }
                    }
                    .padding(.horizontal, 5).padding(.vertical, 3)
                    .familiarGlassSurface(interactive: true, cornerRadius: FamiliarRadius.overlay)
                }
            }
        }
        .padding(.horizontal, FamiliarSpacing.medium)
        .padding(.vertical, FamiliarSpacing.small)
        .photosPicker(isPresented: $showsFullPhotos, selection: $fullPhotoSelection, maxSelectionCount: max(4 - images.count, 1), matching: .images)
        .onChange(of: fullPhotoSelection) { _, items in
            guard !transitionToFullPhotos else { return }
            beginLoadingImages(items)
        }
        .sheet(isPresented: $showsPhotos, onDismiss: showFullPhotosIfNeeded) {
            FamiliarInlinePhotoPickerSheet(selection: photoSelection, limit: max(4 - images.count, 1), onCommit: beginLoadingImages, onAllPhotos: { items in transitionToFullPhotos = true; fullPhotoSelection = items })
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
            FamiliarDraftImagePreviewView(image: item.image) {
                images.removeAll { $0.id == item.id }
            }
            .modifier(FamiliarImageZoom(sourceID: item.id, namespace: imageTransition))
        }
        .fileImporter(isPresented: $showsFiles, allowedContentTypes: Self.allowedFileTypes, allowsMultipleSelection: true, onCompletion: importFiles)
        .alert(item: $notice) { notice in
            Alert(title: Text(notice.title), message: Text(notice.message), dismissButton: .default(Text(String(localized: "common.ok"))))
        }
        .onChange(of: showsSkillPalette) { _, value in actions?.onSkillsChanged(value) }
        .onChange(of: dismissSkillsRevision) { _, _ in showsSkillPalette = false }
        .onChange(of: focus.wrappedValue) { _, focused in
            if focused { showsSkillPalette = false }
            updateModeForFocus(focused)
        }
        .onChange(of: isAnsweringClarification) { _, _ in
            measuredTextHeight = 0
            mode = .compact
            showsSkillPalette = false
        }
        .onChange(of: draftScopeID) { _, _ in cancelDraftTasks() }
        .onDisappear { cancelDraftTasks() }
        .onPreferenceChange(FamiliarComposerTextHeightKey.self) { height in
            guard abs(measuredTextHeight - height) >= 0.5 else { return }
            withAnimation(reduceMotion ? nil : FamiliarMotion.standard) { measuredTextHeight = height }
            updateModeForText()
        }
        .animation(reduceMotion ? nil : FamiliarMotion.standard, value: images.map(\.id))
        .animation(reduceMotion ? nil : FamiliarMotion.standard, value: documents.map(\.id))
        .animation(reduceMotion ? nil : FamiliarMotion.standard, value: importingFileCount)
        .animation(reduceMotion ? nil : FamiliarMotion.standard, value: photoTasks.count)
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
                                .font(FamiliarTypography.caption)
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
            .accessibilityIdentifier("composer.skillMenu")
        }
    }

    private var showsSkills: Bool { showsSkillPalette && !isSending }

    private var selectedSkill: FamiliarSkillMenuItem? {
        skills.first { $0.id == selectedSkillID }
    }

    private var editor: some View {
        ZStack(alignment: .topLeading) {
            if draft.isEmpty {
                Text(String(localized: isAnsweringClarification ? "clarification.custom" : "composer.placeholder"))
                    .font(.system(size: editorFontSize))
                    .lineLimit(1)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 5)
                    .padding(.top, textEditorTopInset)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $draft, selection: $selection)
                .accessibilityIdentifier("composer.input")
                .font(.system(size: editorFontSize))
                .scrollContentBackground(.hidden)
                .scrollIndicators(.hidden)
                .padding(.leading, 0)
                .padding(.top, 0)
                .padding(.trailing, showsExpansion ? 44 : 0)
                .scrollDismissesKeyboard(.interactively)
                .focused(focus)
                .disabled(isAnsweringClarification && !allowsCustomAnswer)
            if showsExpansion {
                HStack {
                    Spacer()
                    Button { toggleFullscreen() } label: {
                        Image(systemName: mode == .fullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                            .foregroundStyle(.secondary).frame(width: 44, height: 44)
                    }
                    .buttonStyle(FamiliarIconButtonStyle())
                    .accessibilityLabel(String(localized: mode == .fullscreen ? "composer.collapse" : "composer.expand"))
                }
            }
        }
        .background {
            GeometryReader { proxy in
                Color.clear.preference(key: FamiliarComposerTextHeightKey.self, value: measuredHeight(width: proxy.size.width))
            }
        }
    }

    private var addButton: some View {
        Menu {
            Button { choose(.camera) } label: { Label(String(localized: "attachment.camera"), systemImage: "camera") }
            Button { choose(.photos) } label: { Label(String(localized: "attachment.photos"), systemImage: "photo") }
            Button { choose(.files) } label: { Label(String(localized: "attachment.files"), systemImage: "paperclip") }
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
        .accessibilityLabel(String(localized: "attachment.add"))
    }

    private var skillMenuButton: some View {
        Button {
            if showsSkillPalette { showsSkillPalette = false }
            else {
                if let selection, case .selection(let range) = selection.indices {
                    savedSelection = range.lowerBound.utf16Offset(in: draft)..<range.upperBound.utf16Offset(in: draft)
                } else { savedSelection = draft.utf16.count..<draft.utf16.count }
                focus.wrappedValue = false
                withAnimation(reduceMotion ? nil : FamiliarMotion.interactiveSpring) { showsSkillPalette = true }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: showsSkillPalette ? "xmark" : "line.3.horizontal")
                    .contentTransition(reduceMotion ? .opacity : .symbolEffect(.replace))
                if !focus.wrappedValue && !hasText { Text(String(localized: "skills.menu")).font(.subheadline.weight(.semibold)) }
            }
            .frame(minWidth: 44, minHeight: 44).padding(.horizontal, !focus.wrappedValue && !hasText ? 10 : 0)
        }
        .buttonStyle(.plain)
        .familiarGlassSurface(interactive: true)
        .disabled(isSending)
        .accessibilityLabel(String(localized: "slash.open"))
        .accessibilityIdentifier("composer.skills")
    }

    @ViewBuilder private var polishButton: some View {
        if onPolish != nil {
            Button { showsSkillPalette = false; focus.wrappedValue = false; onPolish?() } label: {
                Image(systemName: "wand.and.stars").font(.system(size: 20))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain).disabled(isSending || executionBlocked || !hasText)
            .accessibilityLabel(String(localized: "rewrite.title"))
            .accessibilityIdentifier("composer.polish")
        }
    }

    private func restoreEditorFocus() {
        if let savedSelection {
            let lower = min(savedSelection.lowerBound, draft.utf16.count)
            let upper = min(max(lower, savedSelection.upperBound), draft.utf16.count)
            selection = TextSelection(range: String.Index(utf16Offset: lower, in: draft)..<String.Index(utf16Offset: upper, in: draft))
        }
        Task { @MainActor in await Task.yield(); focus.wrappedValue = true }
    }

    private var micButton: some View {
        Button(action: onSpeech) {
            Image(systemName: isListening ? "waveform" : "mic")
                .font(.system(size: FamiliarIconSize.prominent, weight: isListening ? .semibold : .regular))
                .foregroundStyle(isListening ? FamiliarTheme.accent : Color.primary)
                .contentTransition(reduceMotion ? .opacity : .symbolEffect(.replace))
                .symbolEffect(.breathe, isActive: isListening && !reduceMotion)
                .animation(reduceMotion ? nil : FamiliarMotion.micro, value: isListening)
                .frame(
                    width: FamiliarControlSize.minimumHitTarget,
                    height: FamiliarControlSize.minimumHitTarget
                )
        }
        .buttonStyle(FamiliarIconButtonStyle())
        .disabled(isAnsweringClarification)
        .accessibilityLabel(String(localized: isListening ? "speech.stop" : "speech.start"))
        .accessibilityIdentifier("composer.speech")
    }

    private var sendButton: some View {
        Button {
            if isAnsweringClarification { if canSend { onSend() } }
            else if isSending { FamiliarHaptics.shared.perform(.selection); onSend() }
            else if isImporting { return }
            else if hasText || !documents.isEmpty || !images.isEmpty { onSend() }
        } label: {
            Image(systemName: showsStop ? "stop.fill" : "arrow.up")
                .contentTransition(reduceMotion ? .opacity : .symbolEffect(.replace))
                .scaleEffect(showsStop && !reduceMotion ? 0.94 : 1)
                .animation(reduceMotion ? nil : FamiliarMotion.micro, value: showsStop)
                .font(.system(size: FamiliarIconSize.standard, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: FamiliarControlSize.standardVisual, height: FamiliarControlSize.standardVisual)
                .background(canSend ? FamiliarTheme.accent : Color.secondary.opacity(0.28), in: Circle())
                .frame(
                    width: FamiliarControlSize.minimumHitTarget,
                    height: FamiliarControlSize.minimumHitTarget
                )
        }
        .buttonStyle(FamiliarIconButtonStyle())
        .disabled(!canSend || (!isSending && executionBlocked))
        .animation(reduceMotion ? nil : FamiliarMotion.micro, value: canSend)
        .accessibilityIdentifier("composer.send")
        .accessibilityLabel(String(localized: isAnsweringClarification ? "clarification.submit" : (showsStop ? "message.stop" : "message.send")))
        .accessibilityHint(sendDisabledReason ?? "")
    }

    private var sendDisabledReason: String? {
        if isSending { return nil }
        if isImporting { return String(localized: "composer.disabled.importing") }
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
                                previewImage = item
                            } label: {
                                Image(uiImage: item.image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 96, height: 96)
                                    .clipShape(RoundedRectangle(cornerRadius: FamiliarRadius.card, style: .continuous))
                                    .clipped()
                                    .matchedTransitionSource(id: item.id, in: imageTransition)
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
                            .accessibilityLabel(String(localized: "attachment.remove_image"))
                            .offset(x: 8, y: -8)
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
                    if isImporting {
                        HStack(spacing: FamiliarSpacing.small) {
                            ProgressView().controlSize(.small)
                            Text(String(localized: "attachment.processing"))
                                .font(FamiliarTypography.caption)
                        }
                        .padding(.horizontal, FamiliarSpacing.medium)
                        .frame(height: 48)
                        .background(FamiliarTheme.elevatedFill, in: Capsule())
                    }
                }
            }
        }
    }

    private func removeButton(label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: "xmark.circle.fill").symbolRenderingMode(.palette).foregroundStyle(.white, .black.opacity(0.7)) }
            .frame(width: FamiliarControlSize.standardVisual, height: FamiliarControlSize.standardVisual)
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
        setMode(mode == .fullscreen ? .expanded : .fullscreen, emphasized: true)
        Task { @MainActor in await Task.yield(); focus.wrappedValue = true }
    }

    private func updateModeForFocus(_ focused: Bool) {
        if focused, mode == .compact, isLongText {
            setMode(.expanded)
        } else if !focused, mode == .expanded, !isLongText, !hasDraftContent, pendingDestination == nil, !showsCamera, !showsPhotos, !showsFullPhotos, !showsFiles {
            setMode(.compact)
        }
    }

    private func updateModeForText() {
        if isLongText, mode == .compact { setMode(.expanded) }
        else if !isLongText, !focus.wrappedValue, mode == .expanded, !hasDraftContent { setMode(.compact) }
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

    private func measuredHeight(width: CGFloat) -> CGFloat {
        let text = draft.isEmpty ? " " : (draft.hasSuffix("\n") ? draft + " " : draft)
        let bounds = (text as NSString).boundingRect(with: CGSize(width: max(width - 10 - (showsExpansion ? 44 : 0), 1), height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: UIFont.systemFont(ofSize: editorFontSize)], context: nil)
        return max(ceil(bounds.height), CGFloat(max(draft.components(separatedBy: "\n").count, 1)) * lineHeight)
    }

    private func showFullPhotosIfNeeded() {
        guard transitionToFullPhotos else { return }
        transitionToFullPhotos = false
        Task { @MainActor in await Task.yield(); showsFullPhotos = true }
    }

    private func beginAddingCameraImage(_ image: UIImage) {
        guard images.count < 4 else { return }
        let scopeID = draftScopeID, taskID = UUID()
        photoTasks[taskID] = Task { @MainActor in
            defer { photoTasks.removeValue(forKey: taskID) }
            do {
                let attachment = try await FamiliarAttachmentStore.importImage(image)
                guard !Task.isCancelled, scopeID == draftScopeID, images.count < 4 else {
                    FamiliarAttachmentStore.remove(relativePath: attachment.relativePath); return
                }
                images.append(.init(id: attachment.id, image: image, attachment: attachment))
            } catch is CancellationError {} catch { notice = .fileImportFailed(error.localizedDescription) }
        }
    }

    private func beginLoadingImages(_ items: [PhotosPickerItem]) {
        let taskID = UUID()
        photoTasks[taskID] = Task {
            await loadImages(items)
            photoTasks.removeValue(forKey: taskID)
        }
    }

    private func loadImages(_ items: [PhotosPickerItem]) async {
        let scopeID = draftScopeID
        var loaded: [FamiliarDraftImage] = []
        for item in items.prefix(max(4 - images.count, 0)) {
            guard !Task.isCancelled else { FamiliarAttachmentStore.remove(relativePaths: loaded.compactMap { $0.attachment?.relativePath }); return }
            if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                do {
                    let attachment = try await FamiliarAttachmentStore.importImage(image)
                    loaded.append(.init(id: attachment.id, image: image, attachment: attachment))
                } catch is CancellationError {
                    FamiliarAttachmentStore.remove(relativePaths: loaded.compactMap { $0.attachment?.relativePath }); return
                } catch { notice = .fileImportFailed(error.localizedDescription) }
            }
        }
        guard !Task.isCancelled, scopeID == draftScopeID else {
            FamiliarAttachmentStore.remove(relativePaths: loaded.compactMap { $0.attachment?.relativePath }); return
        }
        let accepted = Array(loaded.prefix(max(4 - images.count, 0)))
        let acceptedIDs = Set(accepted.map(\.id))
        FamiliarAttachmentStore.remove(relativePaths: loaded.filter { !acceptedIDs.contains($0.id) }.compactMap { $0.attachment?.relativePath })
        images.append(contentsOf: accepted)
        photoSelection = items
    }

    private static let allowedFileTypes: [UTType] = FamiliarAnyDocService.supportedExtensions
        .sorted()
        .compactMap { UTType(filenameExtension: $0) }

    private func importFiles(_ result: Result<[URL], Error>) {
        do {
            let urls = try result.get().prefix(max(3 - documents.count, 0))
            guard !urls.isEmpty else { return }
            importingFileCount += urls.count
            let scopeID = draftScopeID
            for url in urls {
                let taskID = UUID()
                importTasks[taskID] = Task {
                    defer { finishImport(taskID) }
                    do {
                        let attachment = try await FamiliarAttachmentStore.importDocument(from: url)
                        guard !Task.isCancelled, scopeID == draftScopeID else {
                            FamiliarAttachmentStore.remove(relativePath: attachment.relativePath)
                            return
                        }
                        documents.append(attachment)
                    } catch is CancellationError {
                        return
                    } catch {
                        notice = .fileImportFailed(error.localizedDescription)
                    }
                }
            }
        } catch {
            notice = .fileImportFailed(error.localizedDescription)
        }
    }

    private func finishImport(_ taskID: UUID) {
        guard importTasks.removeValue(forKey: taskID) != nil else { return }
        importingFileCount = max(importingFileCount - 1, 0)
    }

    private func cancelDraftTasks() {
        let fileTasks = importTasks.values
        let imageTasks = photoTasks.values
        importTasks = [:]
        photoTasks = [:]
        importingFileCount = 0
        fileTasks.forEach { $0.cancel() }
        imageTasks.forEach { $0.cancel() }
    }
}

private struct FamiliarDraftImagePreviewView: View {
    @Environment(\.dismiss) private var dismiss
    let image: UIImage
    let onDelete: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .accessibilityLabel(String(localized: "attachment.preview_image", defaultValue: "Image preview"))
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { FamiliarDismissButton() }
                ToolbarItem(placement: .destructiveAction) {
                    Button(role: .destructive) {
                        onDelete()
                        dismiss()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .accessibilityLabel(String(localized: "attachment.remove_image"))
                }
            }
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(.black.opacity(0.72), for: .navigationBar)
        }
        .tint(.white)
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


private struct FamiliarImageZoom: ViewModifier {
    let sourceID: UUID
    let namespace: Namespace.ID
    @Environment(\.familiarReduceMotion) private var reduceMotion
    @ViewBuilder func body(content: Content) -> some View {
        if reduceMotion { content }
        else { content.navigationTransition(.zoom(sourceID: sourceID, in: namespace)) }
    }
}
