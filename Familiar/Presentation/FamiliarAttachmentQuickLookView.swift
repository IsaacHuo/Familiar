import QuickLook
import SwiftUI
import WebKit

struct FamiliarAttachmentPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    let url: URL
    let format: FamiliarFileFormat?

    init(url: URL, format: FamiliarFileFormat? = nil) {
        self.url = url
        self.format = ["html", "htm"].contains(url.pathExtension.lowercased()) ? .html : format
    }

    var body: some View {
        Group {
                if format == .html {
                    FamiliarLocalHTMLPreviewView(url: url)
                } else {
                    FamiliarAttachmentQuickLookView(url: url)
                }
            }
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(url.lastPathComponent)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        FamiliarDismissButton()
                    }
                }
    }
}

private struct FamiliarLocalHTMLPreviewView: UIViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        return WKWebView(frame: .zero, configuration: configuration)
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.load(url, in: webView)
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) { coordinator.task?.cancel(); webView.stopLoading() }

    @MainActor final class Coordinator {
        var loadedURL: URL?
        var task: Task<Void, Never>?
        func load(_ url: URL, in web: WKWebView) {
            guard loadedURL != url else { return }
            loadedURL = url; task?.cancel()
            task = Task { [weak self, weak web] in
                let source = await Task.detached(priority: .userInitiated) { try? String(contentsOf: url, encoding: .utf8) }.value
                guard !Task.isCancelled, self?.loadedURL == url, let web else { return }
                let policy = "<meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'none'; style-src 'unsafe-inline'; img-src data:; font-src data:;\">"
                web.loadHTMLString(policy + (source ?? "<p>" + String(localized: "runtime.ui.file_unavailable") + "</p>"), baseURL: nil)
            }
        }
    }

}

struct FamiliarAttachmentQuickLookView: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {
        guard context.coordinator.url != url else { return }
        context.coordinator.url = url
        uiViewController.reloadData()
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var url: URL

        init(url: URL) {
            self.url = url
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            1
        }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}
