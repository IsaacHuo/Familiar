import SwiftUI
import WebKit

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct FamiliarMarkdownWebView: View {
    @Environment(\.familiarChatScrollSession) private var scrollSession
    enum Mode {
        case compact
        case document
    }

    let markdown: String
    let sources: [FamiliarSource]
    let mode: Mode
    let isStreaming: Bool
    private let usesExternalPresentation: Bool
    let allowsMermaidPreview: Bool
    let onSelectionChange: (String?) -> Void
    var messageActions: FamiliarMessageActions? = nil

    @Environment(\.openURL) private var openURL
    @Environment(\.familiarReduceMotion) private var reduceMotion
    @State private var layoutState = FamiliarMarkdownLayoutState()
    @State private var didFailRendering = false
    @State private var isVisible = false
    @State private var selectingMessage = false
    @State private var messageSelectionControl = FamiliarMessageSelectionControl()
    @State private var previewedDiagram: FamiliarMermaidPreview?
    @State private var presentation: FamiliarStreamingPresentation
    @State private var presentationOwner = UUID()

    init(
        markdown: String,
        sources: [FamiliarSource] = [],
        mode: Mode = .compact,
        isStreaming: Bool = false,
        allowsMermaidPreview: Bool = true,
        onSelectionChange: @escaping (String?) -> Void = { _ in },
        messageActions: FamiliarMessageActions? = nil,
        presentation: FamiliarStreamingPresentation? = nil
    ) {
        let resolved = FamiliarCitation.canonicalized(markdown, sources: sources)
        self.markdown = FamiliarMarkdownNormalizer.normalize(resolved.text)
        self.sources = resolved.sources
        self.mode = mode
        self.isStreaming = isStreaming
        self.allowsMermaidPreview = allowsMermaidPreview
        self.onSelectionChange = onSelectionChange
        self.messageActions = messageActions
        self.usesExternalPresentation = presentation != nil
        _presentation = State(initialValue: presentation ?? FamiliarStreamingPresentation(
            text: FamiliarMarkdownNormalizer.normalize(resolved.text), streaming: isStreaming
        ))
    }

    var body: some View {
        let renderedMarkdown = usesExternalPresentation
            ? FamiliarMarkdownNormalizer.normalize(FamiliarCitation.canonicalized(presentation.text, sources: sources).text)
            : presentation.text
        Group {
            if didFailRendering {
                ScrollView {
                    Group {
                        if let messageActions {
                            FamiliarMessageText(text: messageActions.text, actions: messageActions)
                        } else {
                            FamiliarMarkdownFallbackText(markdown: markdown)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(mode == .document ? FamiliarSpacing.xLarge : 0)
                }
            } else {
                ZStack(alignment: .topLeading) {
                    FamiliarMarkdownPlatformWebView(
                        markdown: renderedMarkdown,
                        sources: sources,
                        height: Binding(get: { layoutState.height }, set: { value in
                            var next = layoutState
                            next.receive(value)
                            var transaction = Transaction(animation: nil)
                            transaction.disablesAnimations = true
                            withTransaction(transaction) { layoutState = next }
                        }),
                        didFailRendering: $didFailRendering,
                        isScrollEnabled: mode == .document,
                        isStreaming: isStreaming,
                        allowsMermaidPreview: allowsMermaidPreview,
                        reduceMotion: reduceMotion,
                        readingRevision: scrollSession?.readingRevision ?? 0,
                        isReading: scrollSession?.mode == .userReading,
                        onSelectionChange: onSelectionChange,
                        onMermaidPreview: { previewedDiagram = .init(source: $0) },
                        openURL: { openURL($0) },
                        messageActions: messageActions,
                        onMessageSelection: { selectingMessage = $0 },
                        onFinishMessageSelection: { messageSelectionControl.finish = $0 }
                    )
                    .frame(height: mode == .document ? nil : layoutState.height)
                    .opacity(mode == .document || layoutState.isMeasured ? 1 : 0)
                    .transaction { transaction in
                        transaction.animation = nil
                        transaction.disablesAnimations = true
                    }

                    if mode == .compact, !layoutState.isMeasured {
                        FamiliarMarkdownFallbackText(markdown: renderedMarkdown)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .allowsHitTesting(false)
                    }
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            if selectingMessage {
                HStack {
                    Spacer()
                    Button(String(localized: "common.done")) { messageSelectionControl.finish?() }
                        .font(.subheadline).frame(minHeight: 44).buttonStyle(.glass).offset(y: -44)
                        .accessibilityIdentifier("message.selection.done")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: mode == .document ? .infinity : nil, alignment: .topLeading)
        .onAppear {
            isVisible = true
            presentation.activate(owner: presentationOwner)
            if !usesExternalPresentation { presentation.receive(markdown, streaming: isStreaming) }
        }
        .onChange(of: markdown) { _, value in if isVisible && !usesExternalPresentation { presentation.receive(value, streaming: isStreaming) } }
        .onChange(of: isStreaming) { _, value in if isVisible && !usesExternalPresentation { presentation.receive(markdown, streaming: value) } }
        .onChange(of: usesExternalPresentation) { _, external in
            if isVisible && !external { presentation.receive(markdown, streaming: isStreaming) }
        }
        .onDisappear { isVisible = false; presentation.deactivate(owner: presentationOwner) }
        .fullScreenCover(item: $previewedDiagram) { diagram in
            NavigationStack {
                FamiliarMarkdownWebView(
                    markdown: "~~~mermaid\n\(diagram.source)\n~~~",
                    mode: .document,
                    allowsMermaidPreview: false
                )
                .padding(FamiliarAISurfaceMetric.spaceM)
                .navigationTitle(String(localized: "mermaid.preview.title", defaultValue: "Diagram preview"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        FamiliarDismissButton()
                    }
                }
            }
        }
    }
}

private struct FamiliarMermaidPreview: Identifiable {
    let id = UUID()
    let source: String
}

struct FamiliarMarkdownFallbackText: View {
    let markdown: String

    var body: some View {
        if let attributed = try? Self.attributed(markdown) {
            Text(attributed)
        } else {
            Text(markdown)
        }
    }

    /// Text does not lay out Foundation's block presentation intents by itself.
    /// Preserve paragraph boundaries while the WebKit document loads.
    static func attributed(_ markdown: String) throws -> AttributedString {
        let parsed = try AttributedString(
            markdown: markdown,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .full,
                failurePolicy: .returnPartiallyParsedIfPossible
            )
        )
        var result = AttributedString()
        var lastBlock: Int?
        for run in parsed.runs {
            let block = run.presentationIntent?.components.first?.identity
            if let lastBlock, let block, block != lastBlock { result += AttributedString("\n\n") }
            var piece = AttributedString(parsed[run.range])
            if let intent = run.presentationIntent?.components.first,
               case .header(let level) = intent.kind {
                piece.font = level == 1 ? .title2.bold() : .headline
            }
            result += piece
            lastBlock = block
        }
        return result
    }
}

enum FamiliarMarkdownHTML {
    static let resourceDirectoryName = "FamiliarMarkdownRenderer"
    static let contentSecurityPolicy = "default-src 'none'; script-src 'self'; style-src 'self' 'unsafe-inline'; font-src 'self'; img-src 'self' data:; connect-src 'none'; media-src 'none'; object-src 'none'; frame-src 'none'; base-uri 'none'; form-action 'none'"
    static let requiredResourceNames = [
        "markdown-it.min.js",
        "purify.min.js",
        "katex.min.js",
        "katex.min.css",
        "highlight.min.js",
        "mermaid.min.js",
        "renderer.css",
        "renderer.js"
    ]

    static var baseDocument: String {
        """
        <!doctype html>
        <html lang="\(Bundle.main.preferredLocalizations.first ?? "en")">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <meta http-equiv="Content-Security-Policy" content="\(contentSecurityPolicy)">
          <link rel="stylesheet" href="katex.min.css">
          <link rel="stylesheet" href="renderer.css">
        </head>
        <body>
          <main id="content"></main>
          <script src="markdown-it.min.js"></script>
          <script src="purify.min.js"></script>
          <script src="katex.min.js"></script>
          <script src="highlight.min.js"></script>
          <script src="mermaid.min.js"></script>
          <script src="renderer.js"></script>
        </body>
        </html>
        """
    }

    static func rendererDirectory(in bundle: Bundle = .main) -> URL? {
        if let resource = bundle.url(
            forResource: "markdown-it.min",
            withExtension: "js",
            subdirectory: resourceDirectoryName
        ) {
            return resource.deletingLastPathComponent()
        }

        if let resourceURL = bundle.resourceURL {
            let directory = resourceURL.appendingPathComponent(resourceDirectoryName, isDirectory: true)
            if FileManager.default.fileExists(atPath: directory.path) {
                return directory
            }
        }

        return bundle.resourceURL
    }

    static func hasRequiredResources(in bundle: Bundle = .main) -> Bool {
        guard let directory = rendererDirectory(in: bundle) else { return false }
        return requiredResourceNames.allSatisfy { name in
            FileManager.default.fileExists(atPath: directory.appendingPathComponent(name).path)
        }
    }

    static func javascriptStringLiteral(_ value: String) -> String {
        guard
            let data = try? JSONSerialization.data(withJSONObject: [value]),
            let arrayLiteral = String(data: data, encoding: .utf8),
            arrayLiteral.count >= 2
        else {
            return "\"\""
        }
        return String(arrayLiteral.dropFirst().dropLast())
    }

    static func sourcesJSONString(_ sources: [FamiliarSource]) -> String {
        let values = sources.map {
            [
                "id": $0.id,
                "title": $0.title,
                "url": $0.url.absoluteString,
                "siteName": $0.siteName ?? $0.url.host ?? ""
            ]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: values),
              let json = String(data: data, encoding: .utf8)
        else { return "[]" }
        return json
            .replacingOccurrences(of: "<", with: "\\u003c")
            .replacingOccurrences(of: ">", with: "\\u003e")
            .replacingOccurrences(of: "&", with: "\\u0026")
    }
}

#if os(iOS)
private struct FamiliarMarkdownPlatformWebView: UIViewRepresentable {
    @Environment(\.familiarSelectedTextSink) private var selectedTextSink
    @Environment(\.familiarChatScrollSession) private var scrollSession
    @Environment(\.familiarReadingGeometry) private var readingGeometry
    @Environment(\.familiarMessageSearchTerm) private var searchTerm
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorSchemeContrast) private var accessibilityContrast
    let markdown: String
    let sources: [FamiliarSource]
    @Binding var height: CGFloat
    @Binding var didFailRendering: Bool
    let isScrollEnabled: Bool
    let isStreaming: Bool
    let allowsMermaidPreview: Bool
    let reduceMotion: Bool
    let readingRevision: Int
    let isReading: Bool
    let onSelectionChange: (String?) -> Void
    let onMermaidPreview: (String) -> Void
    let openURL: (URL) -> Void

    var messageActions: FamiliarMessageActions? = nil
    var onMessageSelection: (Bool) -> Void = { _ in }
    var onFinishMessageSelection: (@escaping () -> Void) -> Void = { _ in }

    func makeCoordinator() -> FamiliarMarkdownWebCoordinator {
        FamiliarMarkdownWebCoordinator(
            height: $height,
            didFailRendering: $didFailRendering,
            onSelectionChange: onSelectionChange,
            onMermaidPreview: onMermaidPreview,
            openURL: openURL
        )
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView = Self.makeWebView(context: context, isScrollEnabled: isScrollEnabled)
        context.coordinator.attach(to: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let previousActions = context.coordinator.messageInteraction.actions?.available
        context.coordinator.messageInteraction.actions = messageActions
        if previousActions != messageActions?.available {
            context.coordinator.setMessageActionsEnabled(messageActions != nil, in: webView)
        }
        context.coordinator.messageInteraction.selectedTextSink = selectedTextSink
        context.coordinator.messageInteraction.scroll = scrollSession
        context.coordinator.messageInteraction.selectionChanged = onMessageSelection
        let interaction = context.coordinator.messageInteraction
        onFinishMessageSelection { [weak interaction] in interaction?.finishSelection() }
        context.coordinator.scrollSession = scrollSession
        context.coordinator.presenterID = readingGeometry?.presenterID
        context.coordinator.refreshReadingAnchor(revision: readingRevision, isReading: isReading, in: webView)
        context.coordinator.setSearchTerm(searchTerm, in: webView)
        context.coordinator.openURL = openURL
        context.coordinator.onSelectionChange = onSelectionChange
        context.coordinator.onMermaidPreview = onMermaidPreview
        context.coordinator.update(markdown: markdown, sources: sources, isStreaming: isStreaming, allowsMermaidPreview: allowsMermaidPreview, reduceMotion: reduceMotion, styleJSON: FamiliarMarkdownStyle.json(colorScheme: colorScheme, size: dynamicTypeSize, contrast: accessibilityContrast), in: webView)
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: FamiliarMarkdownWebCoordinator) {
        coordinator.dismantle(from: webView)
    }

    private static func makeWebView(context: Context, isScrollEnabled: Bool) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = FamiliarMarkdownWebCoordinator.dataStore
        configuration.userContentController = WKUserContentController()
        FamiliarMarkdownWebCoordinator.messageNames.forEach {
            configuration.userContentController.add(context.coordinator, name: $0)
        }

        let webView = FamiliarMessageWebView(frame: .zero, configuration: configuration)
        webView.selectionActions = { [weak webView, weak interaction = context.coordinator.messageInteraction] in
            guard let interaction, interaction.selecting, interaction.selectedTextSink != nil, let messageID = interaction.actions?.messageID else { return [] }
            let source = interaction.actions?.text
            return [UIDeferredMenuElement.uncached { [weak webView, weak interaction] completion in
                guard let webView else { completion([]); return }
                webView.evaluateJavaScript("window.getSelection() ? window.getSelection().toString() : ''") { value, _ in
                    guard let interaction, interaction.actions?.messageID == messageID, interaction.actions?.text == source,
                          let text = value as? String else { completion([]); return }
                    completion(interaction.editActions(text: text))
                }
            }]
        }
        webView.onEscape = { [weak interaction = context.coordinator.messageInteraction] in
            guard interaction?.selecting == true else { return false }
            interaction?.finishSelection(); return true
        }
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.accessibilityIdentifier = "markdown.webview"
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = isScrollEnabled
        webView.scrollView.showsVerticalScrollIndicator = isScrollEnabled
        webView.scrollView.showsHorizontalScrollIndicator = false
        return webView
    }
}

private final class FamiliarMessageWebView: WKWebView {
    var onEscape: (() -> Bool)?
    var selectionActions: (() -> [UIMenuElement])?
    override func buildMenu(with builder: UIMenuBuilder) {
        super.buildMenu(with: builder)
        let actions = selectionActions?() ?? []
        if !actions.isEmpty { builder.remove(menu: .init("familiar.selection")); builder.insertChild(UIMenu(title: String(localized: "selection.actions"), identifier: .init("familiar.selection"), options: .displayInline, children: actions), atEndOfMenu: .root) }
    }
    override func accessibilityPerformEscape() -> Bool { onEscape?() == true || super.accessibilityPerformEscape() }
}
#elseif os(macOS)
private struct FamiliarMarkdownPlatformWebView: NSViewRepresentable {
    let markdown: String
    let sources: [FamiliarSource]
    @Binding var height: CGFloat
    @Binding var didFailRendering: Bool
    let isScrollEnabled: Bool
    let isStreaming: Bool
    let allowsMermaidPreview: Bool
    let reduceMotion: Bool
    let readingRevision: Int
    let isReading: Bool
    let onSelectionChange: (String?) -> Void
    let onMermaidPreview: (String) -> Void
    let openURL: (URL) -> Void

    func makeCoordinator() -> FamiliarMarkdownWebCoordinator {
        FamiliarMarkdownWebCoordinator(
            height: $height,
            didFailRendering: $didFailRendering,
            onSelectionChange: onSelectionChange,
            onMermaidPreview: onMermaidPreview,
            openURL: openURL
        )
    }

    func makeNSView(context: Context) -> WKWebView {
        let webView = Self.makeWebView(context: context)
        context.coordinator.attach(to: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.openURL = openURL
        context.coordinator.onSelectionChange = onSelectionChange
        context.coordinator.onMermaidPreview = onMermaidPreview
        context.coordinator.update(markdown: markdown, sources: sources, isStreaming: isStreaming, allowsMermaidPreview: allowsMermaidPreview, reduceMotion: reduceMotion, in: webView)
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: FamiliarMarkdownWebCoordinator) {
        coordinator.dismantle(from: webView)
    }

    private static func makeWebView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = FamiliarMarkdownWebCoordinator.dataStore
        configuration.userContentController = WKUserContentController()
        FamiliarMarkdownWebCoordinator.messageNames.forEach {
            configuration.userContentController.add(context.coordinator, name: $0)
        }

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        webView.enclosingScrollView?.hasVerticalScroller = false
        webView.enclosingScrollView?.hasHorizontalScroller = false
        return webView
    }
}
#endif

private final class FamiliarMarkdownWebCoordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler, WKUIDelegate {
    // Bundled, network-isolated documents share one ephemeral store.
    static let dataStore = WKWebsiteDataStore.nonPersistent()
    static let selectionMessageName = "selectionChanged"
    static let mermaidPreviewMessageName = "previewMermaid"
    static let messageNames = ["heightChanged", "rendererReady", "renderFailed", "copyCode", "readingShift", "messageInteractionRegions", "messageAccessibilityAction", mermaidPreviewMessageName, selectionMessageName]

    let messageInteraction = FamiliarMessageInteraction()
    private var height: Binding<CGFloat>
    private var didFailRendering: Binding<Bool>
    private weak var webView: WKWebView?
    private var didStartLoading = false
    private var isRendererReady = false
    private var pendingRender = FamiliarMarkdownRenderState(markdown: "", sourcesJSON: "[]", isStreaming: false, allowsMermaidPreview: true, reduceMotion: false, styleJSON: "{}")
    #if os(iOS)
    private var readingRevision = -1
    private var readingActive = false
    func refreshReadingAnchor(revision: Int, isReading: Bool, in web: WKWebView) {
        guard revision != readingRevision || isReading != readingActive else { return }
        readingRevision = revision
        readingActive = isReading
        guard isRendererReady else { return }
        web.evaluateJavaScript("window.FamiliarMarkdown.setReadingTop(\(readingTop(in: web)));", completionHandler: nil)
    }
    private func readingTop(in web: WKWebView) -> String {
        guard let session = scrollSession, session.mode == .userReading, !session.isInteracting,
              let scroll = containingScrollView else { return "null" }
        let y = scroll.convert(CGPoint(x: 0, y: scroll.bounds.minY + scroll.adjustedContentInset.top), to: web).y
        return y > 0 && y < web.bounds.height ? String(Double(y)) : "null"
    }
    weak var scrollSession: FamiliarChatScrollSession?
    var presenterID: UUID?
    private var containingScrollView: UIScrollView? {
        var ancestor = webView?.superview
        while let view = ancestor {
            if let scroll = view as? UIScrollView, scroll.isScrollEnabled { return scroll }
            ancestor = view.superview
        }
        return nil
    }
    #endif
    private var renderedState: FamiliarMarkdownRenderState?
    private var isRendering = false
    private var scheduledRender: DispatchWorkItem?
    private var documentGeneration = UUID()
    private var currentNavigation: WKNavigation?
    private var processRecoveryCount = 0
    private var permanentlyUnavailable = false
    private var lastRenderAt: TimeInterval = 0
    private var renderInterval: FamiliarPerformance.Interval?
    #if os(iOS)
    private var memoryWarningObserver: NSObjectProtocol?
    #endif
    private var deliveredSelection: String?
    private var hasDeliveredSelection = false
    var onSelectionChange: (String?) -> Void
    var onMermaidPreview: (String) -> Void
    var openURL: (URL) -> Void

    init(
        height: Binding<CGFloat>,
        didFailRendering: Binding<Bool>,
        onSelectionChange: @escaping (String?) -> Void,
        onMermaidPreview: @escaping (String) -> Void,
        openURL: @escaping (URL) -> Void
    ) {
        self.height = height
        self.didFailRendering = didFailRendering
        self.onSelectionChange = onSelectionChange
        self.onMermaidPreview = onMermaidPreview
        self.openURL = openURL
    }

    func attach(to webView: WKWebView) {
        if self.webView !== webView {
            invalidateRender()
            didStartLoading = false
            processRecoveryCount = 0
            permanentlyUnavailable = false
        }
        self.webView = webView
        #if os(iOS)
        observeMemoryPressure()
        messageInteraction.attach(to: webView)
        messageInteraction.selectText = { [weak webView] point in
            webView?.becomeFirstResponder()
            webView?.evaluateJavaScript("window.FamiliarMarkdown.selectMessageText(\(point.x), \(point.y));", completionHandler: nil)
        }
        messageInteraction.endTextSelection = { [weak webView] in
            webView?.evaluateJavaScript("window.FamiliarMarkdown.endMessageSelection();", completionHandler: nil)
        }
        #endif
    }

    private var searchTerm = ""
    func setSearchTerm(_ value: String, in web: WKWebView) {
        guard value != searchTerm else { return }
        searchTerm = value
        if messageInteraction.selecting {
            let interaction = messageInteraction
            Task { @MainActor [weak interaction] in interaction?.finishSelection() }
        }
        guard isRendererReady else { return }
        web.evaluateJavaScript("window.FamiliarMarkdown.setSearchTerm(\(FamiliarMarkdownHTML.javascriptStringLiteral(value)));", completionHandler: nil)
    }

    func setMessageActionsEnabled(_ enabled: Bool, in webView: WKWebView) {
        guard isRendererReady else { return }
        let label = FamiliarMarkdownHTML.javascriptStringLiteral(String(localized: "accessibility.message_actions"))
        webView.evaluateJavaScript("window.FamiliarMarkdown.setMessageActions(\(enabled), \(messageAccessibilityActionsJSON), \(label));", completionHandler: nil)
    }

    private var messageAccessibilityActionsJSON: String {
        let values = (messageInteraction.actions?.available ?? []).map { ["id": $0.rawValue, "title": $0.title] }
        let data = try? JSONSerialization.data(withJSONObject: values)
        return data.map { String(decoding: $0, as: UTF8.self) } ?? "[]"
    }

    func update(markdown: String, sources: [FamiliarSource], isStreaming: Bool, allowsMermaidPreview: Bool, reduceMotion: Bool, styleJSON: String = "{}", in webView: WKWebView) {
        self.webView = webView
        if isStreaming {
            deliverSelection(nil)
        }
        pendingRender = .init(
            markdown: markdown,
            sourcesJSON: FamiliarMarkdownHTML.sourcesJSONString(sources),
            isStreaming: isStreaming,
            allowsMermaidPreview: allowsMermaidPreview,
            reduceMotion: reduceMotion,
            styleJSON: styleJSON
        )

        guard !permanentlyUnavailable else { return }
        if renderedState != pendingRender && didFailRendering.wrappedValue {
            let generation = documentGeneration
            DispatchQueue.main.async { [weak self, weak webView] in
                guard let self, let webView, self.webView === webView,
                      self.documentGeneration == generation, !self.permanentlyUnavailable else { return }
                self.didFailRendering.wrappedValue = false
            }
        }

        if !didStartLoading {
            loadDocument(in: webView)
            return
        }

        scheduleRender(isStreaming: isStreaming)
    }

    func dismantle(from webView: WKWebView) {
        messageInteraction.detach()
        #if os(iOS)
        if let memoryWarningObserver { NotificationCenter.default.removeObserver(memoryWarningObserver) }
        memoryWarningObserver = nil
        #endif
        invalidateRender()
        currentNavigation = nil
        if deliveredSelection != nil {
            deliveredSelection = nil
            let callback = onSelectionChange
            DispatchQueue.main.async { callback(nil) }
        }
        Self.messageNames.forEach {
            webView.configuration.userContentController.removeScriptMessageHandler(forName: $0)
        }
        if self.webView === webView { self.webView = nil }
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.stopLoading()
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, let origin = message.webView, origin === webView,
              let envelope = message.body as? [String: Any],
              envelope["documentID"] as? String == documentGeneration.uuidString else { return }
        let payload = envelope["value"]
        let generation = documentGeneration
        DispatchQueue.main.async { [weak self, weak origin] in
            // A completed plain block may now be native. Its retired WebView
            // must not publish a queued height, failure, selection or action.
            guard let self, let origin, self.webView === origin, self.documentGeneration == generation else { return }
            switch message.name {
            case "heightChanged":
                if let value = payload as? NSNumber {
                    let newHeight = max(1, min(CGFloat(truncating: value), 1_000_000))
                    guard abs(self.height.wrappedValue - newHeight) >= 1 else { break }
                    var transaction = Transaction(animation: nil)
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        self.height.wrappedValue = newHeight
                    }
                }
            case "rendererReady":
                self.isRendererReady = true
                self.renderIfReady()
            case "renderFailed":
                self.didFailRendering.wrappedValue = true
            case "readingShift":
                #if os(iOS)
                if let delta = payload as? NSNumber, delta.doubleValue.isFinite {
                    // Let the paired height message settle native layout first.
                    DispatchQueue.main.async { [weak self, weak origin] in
                        guard let self, let origin, self.webView === origin, self.documentGeneration == generation,
                              let session = self.scrollSession,
                              session.acceptsPresenter(self.presenterID), session.mode == .userReading, !session.isInteracting,
                              let scroll = self.containingScrollView else { return }
                        scroll.superview?.layoutIfNeeded()
                        let shift = CGFloat(truncating: delta)
                        let target = min(max(-scroll.adjustedContentInset.top, scroll.contentOffset.y + shift),
                                         max(0, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom))
                        session.contentShifted(target - scroll.contentOffset.y)
                        scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: target), animated: false)
                    }
                }
                #endif
            case "copyCode":
                if let text = payload as? String {
                    Self.copyToPasteboard(text)
                    FamiliarHaptics.shared.perform(.success)
                    FamiliarAccessibility.announce(String(localized: "common.copied"))
                }
            case "messageAccessibilityAction":
                if let value = payload as? String, let action = FamiliarMessageAction(rawValue: value) {
                    self.messageInteraction.perform(action)
                }
            case Self.mermaidPreviewMessageName:
                if let source = payload as? String, !source.isEmpty {
                    self.onMermaidPreview(source)
                }
            case "messageInteractionRegions":
                if let regions = payload as? [[String: Double]] {
                    self.messageInteraction.interactiveRegions = regions.compactMap { value in
                        guard let x = value["x"], let y = value["y"], let w = value["width"], let h = value["height"] else { return nil }
                        return CGRect(x: x, y: y, width: w, height: h)
                    }
                }
            case Self.selectionMessageName:
                guard !self.pendingRender.isStreaming else {
                    self.deliverSelection(nil)
                    break
                }
                guard let payload = payload as? [String: Any], let text = payload["text"] as? String else {
                    self.deliverSelection(nil)
                    break
                }
                let selection = text.trimmingCharacters(in: .whitespacesAndNewlines)
                self.messageInteraction.selectedText = String(selection.prefix(4_000))
                if let rect = payload["rect"] as? [String: Double] {
                    self.messageInteraction.selectedRect = .init(x: rect["x"] ?? 0, y: rect["y"] ?? 0, width: rect["width"] ?? 0, height: rect["height"] ?? 0)
                }
                self.deliverSelection(selection.isEmpty ? nil : String(selection.prefix(4_000)))
                self.messageInteraction.didChangeSelection(hasText: !selection.isEmpty)
            default:
                break
            }
        }
    }

    #if os(iOS)
    func webView(_ webView: WKWebView, willPresentEditMenuWithAnimator animator: any UIEditMenuInteractionAnimating) { messageInteraction.editMenuWillPresent() }
    func webView(_ webView: WKWebView, willDismissEditMenuWithAnimator animator: any UIEditMenuInteractionAnimating) { messageInteraction.editMenuWillDismiss(animator) }
    #endif

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard self.webView === webView, currentNavigation == nil || navigation === currentNavigation else { return }
        isRendererReady = true
        renderIfReady()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard self.webView === webView, currentNavigation == nil || navigation === currentNavigation else { return }
        didFailRendering.wrappedValue = true
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard self.webView === webView, currentNavigation == nil || navigation === currentNavigation else { return }
        didFailRendering.wrappedValue = true
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        guard navigationAction.navigationType == .linkActivated,
              let url = navigationAction.request.url
        else {
            decisionHandler(.allow)
            return
        }

        if url.scheme?.lowercased() == "file", url.fragment != nil {
            decisionHandler(.allow)
            return
        }

        _ = open(url)
        decisionHandler(.cancel)
    }

    private func loadDocument(in webView: WKWebView) {
        didStartLoading = true
        let metadata = "<head><meta name=\"familiar-document\" content=\"" + documentGeneration.uuidString + "\">"
        let html = FamiliarMarkdownHTML.baseDocument.replacingOccurrences(of: "<head>", with: metadata)
        currentNavigation = webView.loadHTMLString(html, baseURL: FamiliarMarkdownHTML.rendererDirectory())
    }

    private func finishRenderInterval() { renderInterval?.end(); renderInterval = nil }

    private func invalidateRender() {
        documentGeneration = UUID()
        scheduledRender?.cancel(); scheduledRender = nil
        isRendering = false; isRendererReady = false; renderedState = nil
        lastRenderAt = 0
        finishRenderInterval()
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard self.webView === webView else { return }
        invalidateRender()
        if processRecoveryCount == 0 {
            processRecoveryCount = 1
            loadDocument(in: webView)
        } else {
            permanentlyUnavailable = true
            didFailRendering.wrappedValue = true
        }
    }

    #if os(iOS)
    private func observeMemoryPressure() {
        guard memoryWarningObserver == nil else { return }
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                _ = try? await self?.webView?.evaluateJavaScript("window.FamiliarMarkdown && window.FamiliarMarkdown.releaseCaches();")
            }
        }
    }
    #endif

    isolated deinit {
        scheduledRender?.cancel(); renderInterval?.end()
        #if os(iOS)
        if let memoryWarningObserver { NotificationCenter.default.removeObserver(memoryWarningObserver) }
        #endif
    }

    private func renderIfReady() {
        guard let webView,
              isRendererReady,
              !isRendering,
              renderedState != pendingRender
        else { return }

        renderInterval = FamiliarPerformance.begin("MarkdownRender")
        let generation = documentGeneration
        lastRenderAt = ProcessInfo.processInfo.systemUptime
        let target = pendingRender
        let literal = FamiliarMarkdownHTML.javascriptStringLiteral(target.markdown)
        let mermaidPreviewLabel = FamiliarMarkdownHTML.javascriptStringLiteral(String(localized: "mermaid.preview.action", defaultValue: "Open full-screen diagram"))
        let copyLabel = FamiliarMarkdownHTML.javascriptStringLiteral(String(localized: "common.copy"))
        let copiedLabel = FamiliarMarkdownHTML.javascriptStringLiteral(String(localized: "common.copied", defaultValue: "Copied"))
        var readingTop = "null"
        #if os(iOS)
        readingTop = self.readingTop(in: webView)
        #endif
        isRendering = true
        webView.evaluateJavaScript("window.FamiliarMarkdown.setReadingTop(\(readingTop)); window.FamiliarMarkdown.setSearchTerm(\(FamiliarMarkdownHTML.javascriptStringLiteral(searchTerm))); window.FamiliarMarkdown.render(\(literal), { sources: \(target.sourcesJSON), streaming: \(target.isStreaming), messageActionsEnabled: \(messageInteraction.actions != nil), messageAccessibilityActions: \(messageAccessibilityActionsJSON), messageActionsLabel: \(FamiliarMarkdownHTML.javascriptStringLiteral(String(localized: "accessibility.message_actions"))), mermaidPreviewEnabled: \(target.allowsMermaidPreview), mermaidPreviewLabel: \(mermaidPreviewLabel), reduceMotion: \(target.reduceMotion), style: \(target.styleJSON), copyLabel: \(copyLabel), copiedLabel: \(copiedLabel) });") { [weak self, weak webView] _, error in
            DispatchQueue.main.async {
                guard let self, let webView, self.webView === webView, self.documentGeneration == generation else { return }
                self.finishRenderInterval()
                if self.renderedState == nil, error == nil { FamiliarPerformance.event("FirstMarkdownRenderCompleted") }
                self.isRendering = false
                if error == nil {
                    self.renderedState = target
                    if self.pendingRender != target {
                        self.scheduleRender(isStreaming: self.pendingRender.isStreaming)
                    }
                } else {
                    self.didFailRendering.wrappedValue = true
                }
            }
        }
    }

    private func scheduleRender(isStreaming: Bool) {
        if !isStreaming {
            scheduledRender?.cancel(); scheduledRender = nil
            renderIfReady()
            return
        }
        let delay = pendingRender.markdown.utf8.count >= 16_384
            ? max(0, 0.12 - (ProcessInfo.processInfo.systemUptime - lastRenderAt)) : 0
        guard delay > 0 else { renderIfReady(); return }
        // Keep the original deadline while replacing the pending value, not a debounce.
        guard scheduledRender == nil else { return }
        let generation = documentGeneration
        let job = DispatchWorkItem { [weak self] in
            guard let self, self.documentGeneration == generation else { return }
            self.scheduledRender = nil
            self.renderIfReady()
        }
        scheduledRender = job
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: job)
    }

    private static func copyToPasteboard(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }

    private func deliverSelection(_ selection: String?) {
        guard !hasDeliveredSelection || deliveredSelection != selection else { return }
        hasDeliveredSelection = true
        deliveredSelection = selection
        onSelectionChange(selection)
    }

    private func open(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              ["http", "https", "mailto"].contains(scheme)
        else {
            return false
        }

        openURL(url)
        return true
    }
}

private struct FamiliarMarkdownRenderState: Equatable {
    let markdown: String
    let sourcesJSON: String
    let isStreaming: Bool
    let allowsMermaidPreview: Bool
    let reduceMotion: Bool
    let styleJSON: String
}
