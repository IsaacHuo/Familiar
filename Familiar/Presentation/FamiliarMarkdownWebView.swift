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
    let allowsMermaidPreview: Bool
    let onSelectionChange: (String?) -> Void

    @Environment(\.openURL) private var openURL
    @Environment(\.familiarReduceMotion) private var reduceMotion
    @State private var contentHeight: CGFloat = 1
    @State private var hasReportedHeight = false
    @State private var didFailRendering = false
    @State private var isVisible = false
    @State private var previewedDiagram: FamiliarMermaidPreview?
    @State private var presentation: FamiliarStreamingPresentation

    init(
        markdown: String,
        sources: [FamiliarSource] = [],
        mode: Mode = .compact,
        isStreaming: Bool = false,
        allowsMermaidPreview: Bool = true,
        onSelectionChange: @escaping (String?) -> Void = { _ in }
    ) {
        self.markdown = FamiliarMarkdownNormalizer.normalize(markdown)
        self.sources = sources
        self.mode = mode
        self.isStreaming = isStreaming
        self.allowsMermaidPreview = allowsMermaidPreview
        self.onSelectionChange = onSelectionChange
        _presentation = State(initialValue: FamiliarStreamingPresentation(
            text: FamiliarMarkdownNormalizer.normalize(markdown), streaming: isStreaming
        ))
    }

    var body: some View {
        Group {
            if didFailRendering {
                ScrollView {
                    FamiliarMarkdownFallbackText(markdown: markdown)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(mode == .document ? FamiliarSpacing.xLarge : 0)
                }
            } else {
                ZStack(alignment: .topLeading) {
                    FamiliarMarkdownPlatformWebView(
                        markdown: presentation.text,
                        sources: sources,
                        height: $contentHeight,
                        didFailRendering: $didFailRendering,
                        isScrollEnabled: mode == .document,
                        isStreaming: isStreaming,
                        allowsMermaidPreview: allowsMermaidPreview,
                        reduceMotion: reduceMotion,
                        readingRevision: scrollSession?.readingRevision ?? 0,
                        isReading: scrollSession?.mode == .userReading,
                        onSelectionChange: onSelectionChange,
                        onMermaidPreview: { previewedDiagram = .init(source: $0) },
                        openURL: { openURL($0) }
                    )
                    .frame(height: mode == .document ? nil : max(1, contentHeight))
                    .transaction { transaction in
                        transaction.animation = nil
                        transaction.disablesAnimations = true
                    }

                    if mode == .compact, !hasReportedHeight {
                        FamiliarMarkdownFallbackText(markdown: presentation.text)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .allowsHitTesting(false)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: mode == .document ? .infinity : nil, alignment: .topLeading)
        .onAppear { isVisible = true; presentation.receive(markdown, streaming: isStreaming) }
        .onChange(of: markdown) { _, value in if isVisible { presentation.receive(value, streaming: isStreaming) } }
        .onChange(of: isStreaming) { _, value in if isVisible { presentation.receive(markdown, streaming: value) } }
        .onDisappear { isVisible = false; presentation.stop() }
        .onChange(of: contentHeight) { _, newHeight in
            if newHeight > 1 { hasReportedHeight = true }
        }
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
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=no">
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
    @Environment(\.familiarChatScrollSession) private var scrollSession
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
        context.coordinator.scrollSession = scrollSession
        context.coordinator.refreshReadingAnchor(revision: readingRevision, isReading: isReading, in: webView)
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

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
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
        webView.setValue(false, forKey: "drawsBackground")
        webView.enclosingScrollView?.hasVerticalScroller = false
        webView.enclosingScrollView?.hasHorizontalScroller = false
        return webView
    }
}
#endif

private final class FamiliarMarkdownWebCoordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    // Bundled, network-isolated documents share one ephemeral store.
    static let dataStore = WKWebsiteDataStore.nonPersistent()
    static let selectionMessageName = "selectionChanged"
    static let mermaidPreviewMessageName = "previewMermaid"
    static let messageNames = ["heightChanged", "rendererReady", "renderFailed", "copyCode", "readingShift", mermaidPreviewMessageName, selectionMessageName]

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
        self.webView = webView
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

        if renderedState != pendingRender && didFailRendering.wrappedValue {
            DispatchQueue.main.async { [weak self] in
                self?.didFailRendering.wrappedValue = false
            }
        }

        if !didStartLoading {
            didStartLoading = true
            webView.loadHTMLString(
                FamiliarMarkdownHTML.baseDocument,
                baseURL: FamiliarMarkdownHTML.rendererDirectory()
            )
            return
        }

        scheduleRender(isStreaming: isStreaming)
    }

    func dismantle(from webView: WKWebView) {
        scheduledRender?.cancel()
        scheduledRender = nil
        if deliveredSelection != nil {
            deliveredSelection = nil
            let callback = onSelectionChange
            DispatchQueue.main.async { callback(nil) }
        }
        Self.messageNames.forEach {
            webView.configuration.userContentController.removeScriptMessageHandler(forName: $0)
        }
        if self.webView === webView {
            self.webView = nil
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            switch message.name {
            case "heightChanged":
                if let value = message.body as? NSNumber {
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
                if let delta = message.body as? NSNumber, delta.doubleValue.isFinite {
                    // Let the paired height message settle native layout first.
                    DispatchQueue.main.async { [weak self] in
                        guard let self, let session = self.scrollSession,
                              session.mode == .userReading, !session.isInteracting,
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
                if let text = message.body as? String {
                    Self.copyToPasteboard(text)
                    FamiliarHaptics.shared.perform(.success)
                }
            case Self.mermaidPreviewMessageName:
                if let source = message.body as? String, !source.isEmpty {
                    self.onMermaidPreview(source)
                }
            case Self.selectionMessageName:
                guard !self.pendingRender.isStreaming else {
                    self.deliverSelection(nil)
                    break
                }
                guard let text = message.body as? String else {
                    self.deliverSelection(nil)
                    break
                }
                let selection = text.trimmingCharacters(in: .whitespacesAndNewlines)
                self.deliverSelection(selection.isEmpty ? nil : String(selection.prefix(4_000)))
            default:
                break
            }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isRendererReady = true
        renderIfReady()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        didFailRendering.wrappedValue = true
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
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

    private func renderIfReady() {
        guard let webView,
              isRendererReady,
              !isRendering,
              renderedState != pendingRender
        else { return }

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
        webView.evaluateJavaScript("window.FamiliarMarkdown.setReadingTop(\(readingTop)); window.FamiliarMarkdown.render(\(literal), { sources: \(target.sourcesJSON), streaming: \(target.isStreaming), mermaidPreviewEnabled: \(target.allowsMermaidPreview), mermaidPreviewLabel: \(mermaidPreviewLabel), reduceMotion: \(target.reduceMotion), style: \(target.styleJSON), copyLabel: \(copyLabel), copiedLabel: \(copiedLabel) });") { [weak self] _, error in
            DispatchQueue.main.async {
                guard let self else { return }
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
        scheduledRender?.cancel()
        scheduledRender = nil
        // Input is already paced. A second debounce would starve a continuous stream.
        renderIfReady()
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
