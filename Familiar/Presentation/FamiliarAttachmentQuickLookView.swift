import QuickLook
import SwiftUI
import WebKit

struct FamiliarAttachmentPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    let url: URL
    let format: FamiliarArtifactFormat?

    init(url: URL, format: FamiliarArtifactFormat? = nil) {
        self.url = url
        self.format = format
    }

    var body: some View {
        NavigationStack {
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
                    ToolbarItem(placement: .cancellationAction) {
                        Button(String(localized: "common.done", defaultValue: "Done")) {
                            dismiss()
                        }
                    }
                }
        }
    }
}

private struct FamiliarLocalHTMLPreviewView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        return WKWebView(frame: .zero, configuration: configuration)
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard let source = try? String(contentsOf: url, encoding: .utf8) else { return }
        let policy = "<meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'none'; style-src 'unsafe-inline'; img-src data:; font-src data:;\">"
        webView.loadHTMLString(policy + source, baseURL: nil)
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
