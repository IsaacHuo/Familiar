import UIKit

/// Creates a window attached to the test host's scene. iOS 26 deprecates
/// `UIWindow(frame:)`; hosted tests always have a connected window scene.
@MainActor
func familiarTestWindow(width: CGFloat, height: CGFloat) -> UIWindow {
    guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else {
        preconditionFailure("Hosted tests require a connected UIWindowScene.")
    }
    let window = UIWindow(windowScene: scene)
    window.frame = CGRect(x: 0, y: 0, width: width, height: height)
    return window
}
