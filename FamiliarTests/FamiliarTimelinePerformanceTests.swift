import SwiftUI
import WebKit
import XCTest
import Darwin
@testable import Familiar

final class FamiliarTimelinePerformanceTests: XCTestCase {
    @MainActor
    private func webCount(_ view: UIView) -> Int {
        if view is WKWebView { return 1 }
        return view.subviews.reduce(0) { $0 + webCount($1) }
    }

    @MainActor
    private func timeline(count: Int, session: FamiliarChatScrollSession = .init()) -> (UIWindow, UIViewController) {
        let controller = FamiliarChatController(dependencies: .init())
        let messages = (0..<count).map { index in
            FamiliarMessageSnapshot(id: UUID(), role: .assistant,
                content: "# Reply \(index)\n\nA paragraph in the conversation.\n\n~~~swift\nlet value = \(index)\n~~~",
                createdAt: Date(timeIntervalSince1970: Double(index)), sequence: index,
                providerID: nil, modelID: nil, attachments: [])
        }
        let timeline = FamiliarMessageTimeline(messages: messages, modelSwitches: [], agentRuns: [],
            liveController: controller, availableUndoKeys: [], completedUndoKeys: [],
            onResolveConfirmation: { _, _ in }, onResolveClarification: { _, _ in },
            onInsertPrompt: { _ in }, onUndo: { _, _ in }, onEdit: { _ in },
            onRetry: { _ in }, onRetryRecovery: { _ in }, scrollSession: session)
        let host = UIHostingController(rootView: NavigationStack { timeline })
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 350, height: 800))
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene { window.windowScene = scene }
        window.rootViewController = host
        let start = ProcessInfo.processInfo.systemUptime
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        let elapsed = ProcessInfo.processInfo.systemUptime - start
        let views = webCount(host.view)
        print("TIMELINE_METRIC count=\(count) webViews=\(views) initialLayoutSeconds=\(elapsed)")
        XCTAssertGreaterThan(views, 0)
        XCTAssertLessThanOrEqual(views, 8)
        return (window, host)
    }

    @MainActor func testHistory100InitialNativeLayout() { timeline(count: 100).0.isHidden = true }
    @MainActor func testHistory300InitialNativeLayout() { timeline(count: 300).0.isHidden = true }

    @MainActor private func nativeScroll(in view: UIView) -> UIScrollView? {
        if view is WKWebView { return nil }
        if let scroll = view as? UIScrollView, scroll.isScrollEnabled { return scroll }
        return view.subviews.lazy.compactMap { self.nativeScroll(in: $0) }.first
    }

    private func residentMB() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Double(info.resident_size) / 1_048_576 : 0
    }

    @MainActor func testHistoryScrollRetainsBoundedNativeWebViews() async throws {
        for count in [100, 300] {
            let session = FamiliarChatScrollSession()
            let (window, host) = timeline(count: count, session: session)
            defer { window.isHidden = true }
            try await Task.sleep(for: .milliseconds(200))
            let scroll = try XCTUnwrap(nativeScroll(in: host.view))
            session.userBegan()
            var maximumViews = 0, costs: [Double] = []
            var peak = residentMB()
            for _ in 0..<20 {
                let start = ProcessInfo.processInfo.systemUptime
                scroll.setContentOffset(CGPoint(x: 0, y: max(-scroll.adjustedContentInset.top,
                    scroll.contentOffset.y - scroll.bounds.height * 0.8)), animated: false)
                host.view.layoutIfNeeded()
                costs.append(ProcessInfo.processInfo.systemUptime - start)
                try await Task.sleep(for: .milliseconds(60))
                maximumViews = max(maximumViews, webCount(host.view))
                peak = max(peak, residentMB())
            }
            session.userEnded()
            XCTAssertLessThan(maximumViews, count / 2)
            XCTAssertLessThan(costs.max() ?? 0, 1)
            print("TIMELINE_SCROLL count=\(count) steps=20 maxWebViews=\(maximumViews) medianLayoutSeconds=\(costs.sorted()[10]) maxLayoutSeconds=\(costs.max() ?? 0) peakNativeResidentMB=\(peak)")
        }
    }
}
