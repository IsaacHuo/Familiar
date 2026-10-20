import SwiftUI
import UIKit

/// SwiftUI onDisappear can arrive after an interactive pop has already laid out
/// both pages. Suspend reading corrections at UIKit's transition boundary.
struct FamiliarChatReadingLifecycle: UIViewControllerRepresentable {
    let session: FamiliarChatScrollSession
    let presenterID: UUID
    var sendPresentation: FamiliarSendPresentation? = nil

    func makeUIViewController(context: Context) -> Controller {
        Controller(session: session, presenterID: presenterID, sendPresentation: sendPresentation)
    }
    func updateUIViewController(_ controller: Controller, context: Context) {}
    static func dismantleUIViewController(_ controller: Controller, coordinator: ()) {
        controller.session.endPresentation(controller.presenterID)
    }

    final class Controller: UIViewController {
        let session: FamiliarChatScrollSession
        let presenterID: UUID
        let sendPresentation: FamiliarSendPresentation?
        init(session: FamiliarChatScrollSession, presenterID: UUID, sendPresentation: FamiliarSendPresentation? = nil) {
            self.session = session; self.presenterID = presenterID; self.sendPresentation = sendPresentation
            super.init(nibName: nil, bundle: nil)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func loadView() {
            view = UIView(); view.isUserInteractionEnabled = false
        }
        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            session.endPresentation(presenterID)
            sendPresentation?.cancel()
            transitionCoordinator?.animate(alongsideTransition: nil) { [weak self] context in
                guard context.isCancelled, let self, self.viewIfLoaded?.window != nil else { return }
                self.session.beginPresentation(self.presenterID)
            }
        }
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            // An interactive pop can be cancelled; the same page owns reading again.
            if !session.acceptsPresenter(presenterID) { session.beginPresentation(presenterID) }
        }
    }
}
