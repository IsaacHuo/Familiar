import SwiftUI
import SafariServices

struct FamiliarWebDestination: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

struct FamiliarSafariView: UIViewControllerRepresentable {
    let url: URL
    let onFinish: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let viewController = SFSafariViewController(url: url)
        viewController.dismissButtonStyle = .close
        viewController.delegate = context.coordinator
        return viewController
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}

    final class Coordinator: NSObject, SFSafariViewControllerDelegate {
        let onFinish: () -> Void

        init(onFinish: @escaping () -> Void) {
            self.onFinish = onFinish
        }

        func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
            onFinish()
        }
    }
}

/// A result Sheet owns its browser presentation so URLs never compete with the Chat's Sheet.
struct FamiliarSheetBrowser: ViewModifier {
    @State private var destination: FamiliarWebDestination?
    func body(content: Content) -> some View {
        content
            .environment(\.openURL, OpenURLAction { url in
                guard FamiliarConversationURLRouter.shouldOpenInApp(url) else { return .systemAction }
                destination = .init(url: url)
                return .handled
            })
            .sheet(item: $destination) { item in
                FamiliarSafariView(url: item.url) { destination = nil }
                    .ignoresSafeArea()
                    .presentationSizing(.page)
                    .presentationDragIndicator(.visible)
            }
    }
}
