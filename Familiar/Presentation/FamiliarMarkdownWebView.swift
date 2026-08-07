import SwiftUI
import WebKit

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct FamiliarMarkdownWebView: View {
    enum Mode {
        case compact
        case document
    }

    let markdown: String
    let mode: Mode

    @Environment(\.openURL) private var openURL
    @State private var contentHeight: CGFloat = 1
    @State private var didFailRendering = false

    init(markdown: String, mode: Mode = .compact) {
        self.markdown = FamiliarMarkdownNormalizer.normalize(markdown)
        self.mode = mode
    }

    var body: some View {
        Group {
            if didFailRendering {
                ScrollView {
                    FamiliarMarkdownFallbackText(markdown: markdown)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(mode == .document ? AppSpacing.page : 0)
                }
            } else {
                FamiliarMarkdownPlatformWebView(
                    markdown: markdown,
                    height: $contentHeight,
                    didFailRendering: $didFailRendering,
                    isScrollEnabled: mode == .document,
                    openURL: { openURL($0) }
                )
                .frame(height: mode == .document ? nil : max(1, contentHeight))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct FamiliarMarkdownFallbackText: View {
    let markdown: String

    var body: some View {
        if let attributed = try? AttributedString(
            markdown: markdown,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .full,
                failurePolicy: .returnPartiallyParsedIfPossible
            )
        ) {
            Text(attributed)
        } else {
            Text(markdown)
        }
    }
}

enum FamiliarMarkdownHTML {
    static let resourceDirectoryName = "FamiliarMarkdownRenderer"
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
          <meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'self'; style-src 'self' 'unsafe-inline'; font-src 'self'; img-src https: data:; connect-src 'none'; media-src 'none'; object-src 'none'; frame-src 'none'; base-uri 'none'; form-action 'none'">
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
}

#if os(iOS)
private struct FamiliarMarkdownPlatformWebView: UIViewRepresentable {
    let markdown: String
    @Binding var height: CGFloat
    @Binding var didFailRendering: Bool
    let isScrollEnabled: Bool
    let openURL: (URL) -> Void

    func makeCoordinator() -> FamiliarMarkdownWebCoordinator {
        FamiliarMarkdownWebCoordinator(
            height: $height,
            didFailRendering: $didFailRendering,
            openURL: openURL
        )
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView = Self.makeWebView(context: context, isScrollEnabled: isScrollEnabled)
        context.coordinator.attach(to: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.openURL = openURL
        context.coordinator.update(markdown: markdown, in: webView)
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: FamiliarMarkdownWebCoordinator) {
        coordinator.dismantle(from: webView)
    }

    private static func makeWebView(context: Context, isScrollEnabled: Bool) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController = WKUserContentController()
        FamiliarMarkdownWebCoordinator.messageNames.forEach {
            configuration.userContentController.add(context.coordinator, name: $0)
        }

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
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
    @Binding var height: CGFloat
    @Binding var didFailRendering: Bool
    let isScrollEnabled: Bool
    let openURL: (URL) -> Void

    func makeCoordinator() -> FamiliarMarkdownWebCoordinator {
        FamiliarMarkdownWebCoordinator(
            height: $height,
            didFailRendering: $didFailRendering,
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
        context.coordinator.update(markdown: markdown, in: webView)
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: FamiliarMarkdownWebCoordinator) {
        coordinator.dismantle(from: webView)
    }

    private static func makeWebView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
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
    static let messageNames = ["heightChanged", "rendererReady", "renderFailed", "copyCode"]

    private var height: Binding<CGFloat>
    private var didFailRendering: Binding<Bool>
    private weak var webView: WKWebView?
    private var didStartLoading = false
    private var isRendererReady = false
    private var pendingMarkdown = ""
    private var renderedMarkdown: String?
    var openURL: (URL) -> Void

    init(
        height: Binding<CGFloat>,
        didFailRendering: Binding<Bool>,
        openURL: @escaping (URL) -> Void
    ) {
        self.height = height
        self.didFailRendering = didFailRendering
        self.openURL = openURL
    }

    func attach(to webView: WKWebView) {
        self.webView = webView
    }

    func update(markdown: String, in webView: WKWebView) {
        self.webView = webView
        pendingMarkdown = markdown

        if renderedMarkdown != markdown {
            didFailRendering.wrappedValue = false
        }

        if !didStartLoading {
            didStartLoading = true
            webView.loadHTMLString(
                FamiliarMarkdownHTML.baseDocument,
                baseURL: FamiliarMarkdownHTML.rendererDirectory()
            )
            return
        }

        renderIfReady()
    }

    func dismantle(from webView: WKWebView) {
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
                    self.height.wrappedValue = max(1, min(CGFloat(truncating: value), 16_000))
                }
            case "rendererReady":
                self.isRendererReady = true
                self.renderIfReady()
            case "renderFailed":
                self.didFailRendering.wrappedValue = true
            case "copyCode":
                if let text = message.body as? String {
                    Self.copyToPasteboard(text)
                }
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
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard navigationAction.navigationType == .linkActivated,
              let url = navigationAction.request.url
        else {
            decisionHandler(.allow)
            return
        }

        if open(url) {
            decisionHandler(.cancel)
        } else {
            decisionHandler(.allow)
        }
    }

    private func renderIfReady() {
        guard isRendererReady, renderedMarkdown != pendingMarkdown else { return }
        let literal = FamiliarMarkdownHTML.javascriptStringLiteral(pendingMarkdown)
        webView?.evaluateJavaScript("window.FamiliarMarkdown.render(\(literal));") { [weak self] _, error in
            DispatchQueue.main.async {
                if error == nil {
                    self?.renderedMarkdown = self?.pendingMarkdown
                } else {
                    self?.didFailRendering.wrappedValue = true
                }
            }
        }
    }

    private static func copyToPasteboard(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
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
