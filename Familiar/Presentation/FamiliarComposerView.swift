import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import UIKit

private struct FamiliarDraftImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

private struct FamiliarDraftFile: Identifiable {
    let id = UUID()
    let name: String
    let typeIdentifier: String
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

private struct FamiliarComposerTextHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct FamiliarComposerLayout: Layout {
    let mode: FamiliarComposerMode
    let editorHeight: CGFloat
    private let control: CGFloat = 44

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let fallback = CGSize(width: 320, height: desiredHeight)
        let proposed = proposal.replacingUnspecifiedDimensions(by: fallback)
        return CGSize(width: proposed.width, height: mode == .fullscreen ? proposed.height : desiredHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 4 else { return }
        if mode == .compact {
            let y = bounds.minY + max((bounds.height - control) / 2, 0)
            let sendX = bounds.maxX - control
            let micX = sendX - 2 - control
            let editorX = bounds.minX + control + 4
            let editorWidth = max(micX - 4 - editorX, 1)
            subviews[0].place(at: CGPoint(x: bounds.minX, y: y), anchor: .topLeading, proposal: .init(width: control, height: control))
            subviews[1].place(at: CGPoint(x: editorX, y: y), anchor: .topLeading, proposal: .init(width: editorWidth, height: control))
            subviews[2].place(at: CGPoint(x: micX, y: y), anchor: .topLeading, proposal: .init(width: control, height: control))
            subviews[3].place(at: CGPoint(x: sendX, y: y), anchor: .topLeading, proposal: .init(width: control, height: control))
        } else {
            let toolbarY = bounds.maxY - control
            let textHeight = max(toolbarY - 8 - bounds.minY, 1)
            let sendX = bounds.maxX - control
            let micX = sendX - 2 - control
            subviews[0].place(at: CGPoint(x: bounds.minX, y: toolbarY), anchor: .topLeading, proposal: .init(width: control, height: control))
            subviews[1].place(at: CGPoint(x: bounds.minX, y: bounds.minY), anchor: .topLeading, proposal: .init(width: bounds.width, height: textHeight))
            subviews[2].place(at: CGPoint(x: micX, y: toolbarY), anchor: .topLeading, proposal: .init(width: control, height: control))
            subviews[3].place(at: CGPoint(x: sendX, y: toolbarY), anchor: .topLeading, proposal: .init(width: control, height: control))
        }
    }

    private var desiredHeight: CGFloat {
        mode == .compact ? control : editorHeight + 8 + control
    }
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
                    Image(systemName: "chevron.left").frame(width: 44, height: 44)
                }
                .familiarGlassCircle(interactive: true)
                .accessibilityLabel(String(localized: "attachment.close_photos"))
                Spacer()
                Button {
                    if pending.isEmpty { onAllPhotos(pending) } else { onCommit(pending) }
                    dismiss()
                } label: {
                    Text(pending.isEmpty ? String(localized: "attachment.all_photos") : String(format: String(localized: "attachment.add_photos_count"), pending.count))
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 18)
                        .frame(height: 44)
                }
                .familiarGlassSurface(interactive: true)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }
}

struct FamiliarComposer: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var draft: String
    let isSending: Bool
    let focus: FocusState<Bool>.Binding
    let onSpeech: () -> Void
    let onSend: () -> Void

    @State private var mode: FamiliarComposerMode = .compact
    @State private var measuredTextHeight: CGFloat = 0
    @State private var images: [FamiliarDraftImage] = []
    @State private var files: [FamiliarDraftFile] = []
    @State private var photoSelection: [PhotosPickerItem] = []
    @State private var fullPhotoSelection: [PhotosPickerItem] = []
    @State private var showsAddMenu = false
    @State private var pendingDestination: FamiliarComposerAddDestination?
    @State private var showsCamera = false
    @State private var showsPhotos = false
    @State private var showsFullPhotos = false
    @State private var transitionToFullPhotos = false
    @State private var showsFiles = false
    @State private var notice: FamiliarComposerNotice?
    private let availableHeight: CGFloat
    private static let editorFontSize: CGFloat = 20
    private static let lineHeight = UIFont.systemFont(ofSize: editorFontSize).lineHeight

    init(draft: Binding<String>, isSending: Bool, focus: FocusState<Bool>.Binding, onSpeech: @escaping () -> Void, onSend: @escaping () -> Void, availableHeight: CGFloat = UIScreen.main.bounds.height) {
        _draft = draft
        self.isSending = isSending
        self.focus = focus
        self.onSpeech = onSpeech
        self.onSend = onSend
        self.availableHeight = availableHeight
    }

    private var hasText: Bool { !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var canSend: Bool { hasText || hasDraftContent || isSending }
    private var hasDraftContent: Bool { !images.isEmpty || !files.isEmpty }
    private var effectiveTextHeight: CGFloat { max(measuredTextHeight, CGFloat(max(draft.components(separatedBy: "\n").count, 1)) * Self.lineHeight) }
    private var isLongText: Bool { effectiveTextHeight >= Self.lineHeight * 4 - 0.5 }
    private var showsExpansion: Bool { mode == .fullscreen || isLongText }
    private var editorHeight: CGFloat { min(max(effectiveTextHeight + 18, 44), Self.lineHeight * 4 + 20) }
    private var controlsHeight: CGFloat { mode == .compact ? 44 : editorHeight + 8 + 44 }
    private var fullscreenHeight: CGFloat { min(max(availableHeight * 0.8, 240), availableHeight) }

    var body: some View {
        VStack(spacing: 8) {
            draftPreview
            FamiliarComposerLayout(mode: mode, editorHeight: editorHeight) {
                addButton
                editor
                micButton
                sendButton
            }
            .frame(height: mode == .fullscreen ? nil : controlsHeight)
            .frame(maxHeight: mode == .fullscreen ? .infinity : nil)
        }
        .padding(.horizontal, 8)
        .padding(.top, hasDraftContent ? 10 : 4)
        .padding(.bottom, 4)
        .frame(height: mode == .fullscreen ? fullscreenHeight : nil, alignment: .bottom)
        .familiarGlassSurface(interactive: true)
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .photosPicker(isPresented: $showsFullPhotos, selection: $fullPhotoSelection, maxSelectionCount: max(4 - images.count, 1), matching: .images)
        .onChange(of: fullPhotoSelection) { _, items in
            guard !transitionToFullPhotos else { return }
            Task { await loadImages(items) }
        }
        .sheet(isPresented: $showsPhotos, onDismiss: showFullPhotosIfNeeded) {
            FamiliarInlinePhotoPickerSheet(selection: photoSelection, limit: max(4 - images.count, 1), onCommit: { items in Task { await loadImages(items) } }, onAllPhotos: { items in transitionToFullPhotos = true; fullPhotoSelection = items })
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showsCamera) {
            FamiliarCameraView { image in
                images.append(.init(image: image))
            }
            .presentationDetents([.fraction(0.62)])
            .presentationBackground(.black)
        }
        .fileImporter(isPresented: $showsFiles, allowedContentTypes: Self.allowedFileTypes, allowsMultipleSelection: true, onCompletion: importFiles)
        .popover(isPresented: $showsAddMenu, attachmentAnchor: .point(.top), arrowEdge: .bottom) {
            addMenu.presentationCompactAdaptation(.popover)
        }
        .alert(item: $notice) { notice in
            Alert(title: Text(notice.title), message: Text(notice.message), dismissButton: .default(Text(String(localized: "common.ok"))))
        }
        .onChange(of: focus.wrappedValue) { _, focused in updateModeForFocus(focused) }
        .onPreferenceChange(FamiliarComposerTextHeightKey.self) { measuredTextHeight = $0; updateModeForText() }
    }

    private var editor: some View {
        ZStack(alignment: .topLeading) {
            if draft.isEmpty {
                Text(String(localized: "composer.placeholder"))
                    .font(.system(size: Self.editorFontSize))
                    .foregroundStyle(.tertiary)
                    .padding(.leading, mode == .compact ? 5 : 14)
                    .padding(.top, focus.wrappedValue ? 6 : 8)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $draft)
                .font(.system(size: Self.editorFontSize))
                .scrollContentBackground(.hidden)
                .scrollIndicators(.hidden)
                .padding(.leading, mode == .compact ? 0 : 9)
                .padding(.trailing, showsExpansion ? 42 : 0)
                .padding(.top, focus.wrappedValue ? 6 : 0)
                .focused(focus)
            if showsExpansion {
                HStack {
                    Spacer()
                    Button { toggleFullscreen() } label: {
                        Image(systemName: mode == .fullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                            .foregroundStyle(.secondary).frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
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
        Button { showsAddMenu.toggle() } label: { Image(systemName: "plus").font(.system(size: 22)).frame(width: 44, height: 44) }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "attachment.add"))
    }

    private var micButton: some View {
        Button(action: onSpeech) { Image(systemName: "mic").font(.system(size: 23)).frame(width: 44, height: 44) }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "speech.start"))
    }

    private var sendButton: some View {
        Button {
            if isSending { onSend() }
            else if !images.isEmpty { notice = .imageBlocked }
            else if !files.isEmpty { notice = .fileBlocked }
            else if hasText { onSend() }
        } label: {
            Image(systemName: isSending ? "stop.fill" : "arrow.up")
                .font(.system(size: 14, weight: .bold)).foregroundStyle(.white).frame(width: 36, height: 36)
                .background(canSend ? FamiliarTheme.accent : Color.secondary.opacity(0.28), in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(!canSend)
        .accessibilityLabel(String(localized: isSending ? "message.stop" : "message.send"))
    }

    @ViewBuilder private var draftPreview: some View {
        if hasDraftContent {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(images) { item in
                        ZStack(alignment: .topTrailing) {
                            Image(uiImage: item.image).resizable().scaledToFill().frame(width: 92, height: 76).clipShape(RoundedRectangle(cornerRadius: 16)).clipped()
                            removeButton(label: String(localized: "attachment.remove_image")) { images.removeAll { $0.id == item.id } }
                        }
                    }
                    ForEach(files) { file in
                        HStack(spacing: 7) {
                            Image(systemName: "doc.text").foregroundStyle(FamiliarTheme.accent)
                            Text(file.name).font(.caption).lineLimit(1)
                            removeButton(label: String(localized: "attachment.remove_file")) { files.removeAll { $0.id == file.id } }
                        }
                        .padding(.leading, 10).frame(height: 44).background(FamiliarTheme.elevatedFill, in: Capsule())
                    }
                }
            }
        }
    }

    private func removeButton(label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: "xmark.circle.fill").symbolRenderingMode(.palette).foregroundStyle(.white, .black.opacity(0.7)) }
            .frame(width: 36, height: 36).accessibilityLabel(label)
    }

    private var addMenu: some View {
        VStack(spacing: 0) {
            addMenuButton("attachment.camera", systemImage: "camera") { choose(.camera) }
            addMenuButton("attachment.photos", systemImage: "photo") { choose(.photos) }
            addMenuButton("attachment.files", systemImage: "paperclip") { choose(.files) }
        }
        .padding(.vertical, 8).frame(width: 250)
    }

    private func addMenuButton(_ key: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) { Image(systemName: systemImage).frame(width: 32); Text(String(localized: String.LocalizationValue(key))); Spacer() }
                .font(.system(size: 18)).padding(.horizontal, 16).frame(height: 52).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func choose(_ destination: FamiliarComposerAddDestination) {
        pendingDestination = destination
        showsAddMenu = false
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
        setMode(mode == .fullscreen ? .expanded : .fullscreen, response: 0.38)
        Task { @MainActor in await Task.yield(); focus.wrappedValue = true }
    }

    private func updateModeForFocus(_ focused: Bool) {
        if focused, mode == .compact {
            setMode(.expanded)
        } else if !focused, mode == .expanded, !isLongText, !hasDraftContent, !showsAddMenu, pendingDestination == nil, !showsCamera, !showsPhotos, !showsFullPhotos, !showsFiles {
            setMode(.compact)
        }
    }

    private func updateModeForText() {
        if isLongText, mode == .compact { setMode(.expanded) }
        else if !isLongText, !focus.wrappedValue, mode == .expanded, !hasDraftContent { setMode(.compact) }
    }

    private func setMode(_ newMode: FamiliarComposerMode, response: Double = 0.32) {
        if reduceMotion {
            mode = newMode
        } else {
            withAnimation(.spring(response: response, dampingFraction: 0.86)) {
                mode = newMode
            }
        }
    }

    private func measuredHeight(width: CGFloat) -> CGFloat {
        let text = draft.isEmpty ? " " : (draft.hasSuffix("\n") ? draft + " " : draft)
        let bounds = (text as NSString).boundingRect(with: CGSize(width: max(width - 54, 1), height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: UIFont.systemFont(ofSize: Self.editorFontSize)], context: nil)
        return max(ceil(bounds.height), CGFloat(max(draft.components(separatedBy: "\n").count, 1)) * Self.lineHeight)
    }

    private func showFullPhotosIfNeeded() {
        guard transitionToFullPhotos else { return }
        transitionToFullPhotos = false
        Task { @MainActor in await Task.yield(); showsFullPhotos = true }
    }

    private func loadImages(_ items: [PhotosPickerItem]) async {
        var loaded: [FamiliarDraftImage] = []
        for item in items.prefix(max(4 - images.count, 0)) {
            if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) { loaded.append(.init(image: image)) }
        }
        await MainActor.run { images.append(contentsOf: loaded.prefix(max(4 - images.count, 0))); photoSelection = items }
    }

    private static let allowedFileTypes: [UTType] = [.pdf, UTType(filenameExtension: "txt")!, UTType(filenameExtension: "md")!]

    private func importFiles(_ result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            for url in urls.prefix(max(3 - files.count, 0)) {
                let accessed = url.startAccessingSecurityScopedResource(); defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                let type = try url.resourceValues(forKeys: [.contentTypeKey]).contentType
                guard Self.allowedFileTypes.contains(where: { $0.identifier == type?.identifier }) else { continue }
                files.append(.init(name: url.lastPathComponent, typeIdentifier: type?.identifier ?? UTType.data.identifier))
            }
        } catch { notice = .fileImportFailed }
    }
}

private struct FamiliarComposerNotice: Identifiable {
    enum Kind { case imageBlocked, fileBlocked, fileImportFailed }
    let id = UUID()
    let kind: Kind
    var title: String {
        switch kind {
        case .imageBlocked: return String(localized: "attachment.image_send_blocked_title")
        case .fileBlocked: return String(localized: "attachment.file_send_blocked_title")
        case .fileImportFailed: return String(localized: "attachment.file_import_failed_title")
        }
    }
    var message: String {
        switch kind {
        case .imageBlocked: return String(localized: "attachment.image_send_blocked_detail")
        case .fileBlocked: return String(localized: "attachment.file_send_blocked_detail")
        case .fileImportFailed: return String(localized: "attachment.file_import_failed")
        }
    }
    static let imageBlocked = FamiliarComposerNotice(kind: .imageBlocked)
    static let fileBlocked = FamiliarComposerNotice(kind: .fileBlocked)
    static let fileImportFailed = FamiliarComposerNotice(kind: .fileImportFailed)
}
