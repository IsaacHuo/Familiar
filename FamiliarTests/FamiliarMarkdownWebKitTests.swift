import WebKit
import XCTest
import SwiftUI
import Observation
@testable import Familiar

final class FamiliarMarkdownWebKitTests: XCTestCase {
    @MainActor @Observable
    fileprivate final class Content {
        var text = "# Title\n\nGrowing"
        var streaming = true
    }

    private struct Host: View {
        let content: Content
        var body: some View {
            FamiliarMarkdownWebView(markdown: content.text, isStreaming: content.streaming)
        }
    }

    @MainActor @Observable
    fileprivate final class TimelineContent {
        var messages: [FamiliarMessageSnapshot] = []
        var runs: [FamiliarAgentRunSnapshot] = []
        let controller = FamiliarChatController(dependencies: .init())
    }

    private struct TimelineHost: View {
        let content: TimelineContent
        var body: some View {
            NavigationStack {
                FamiliarMessageTimeline(messages: content.messages, modelSwitches: [], agentRuns: content.runs,
                    liveController: content.controller, availableUndoKeys: [], completedUndoKeys: [],
                    onResolveConfirmation: { _, _ in }, onResolveClarification: { _, _ in },
                    onInsertPrompt: { _ in }, onUndo: { _, _ in }, onEdit: { _ in },
                    onRetry: { _ in }, onRetryRecovery: { _ in })
            }
        }
    }

    @MainActor
    func testTimelineCheckpointDoesNotDismantleLiveMarkdown() async throws {
        let content = TimelineContent()
        let runID = UUID().uuidString, messageID = UUID(), blockID = UUID(), date = Date()
        let body = "# Live\n\nGrowing"
        let live = FamiliarLiveResponseBlock(id: blockID, assistantTurnID: runID + ":turn:0",
            order: 1, startedAt: date, content: body)
        content.controller.surfaces.apply(.init(runID: runID, sequence: 0, timestamp: date,
            assistantTurnID: nil, payload: .runPhaseChanged(.starting)))
        content.controller.streamingResponseBlocks = [live]
        content.controller.runtimeContentBlocks = [.text(.init(live))]
        let host = UIHostingController(rootView: TimelineHost(content: content))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 350, height: 800))
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene { window.windowScene = scene }
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        host.view.layoutIfNeeded()
        let original = try XCTUnwrap(webViews(in: host.view).first)
        try await Task.sleep(for: .milliseconds(100))
        let block = FamiliarResponseBlockSnapshot(id: blockID, assistantTurnID: live.assistantTurnID,
            messageID: messageID, kind: .markdown, order: 1, state: .completed, content: body,
            payloadJSON: "{}", schemaVersion: 1, startedAt: date, endedAt: date, contentHash: "")
        content.messages = [.init(id: messageID, role: .assistant, content: body, createdAt: date, sequence: 1,
            providerID: nil, modelID: nil, attachments: [], responseBlocks: [block], finalResponseBlockID: blockID)]
        content.runs = [.init(id: runID, responseMessageID: messageID, status: .completed,
            startedAt: date, finishedAt: date, responseBlocks: [block])]
        content.controller.surfaces = FamiliarSurfaceStore()
        content.controller.streamingResponseBlocks = []
        content.controller.runtimeContentBlocks = []
        try await Task.sleep(for: .milliseconds(200))
        host.view.layoutIfNeeded()
        XCTAssertEqual(webViews(in: host.view).count, 1)
        XCTAssertTrue(webViews(in: host.view).first === original)
    }

    @MainActor
    private func webViews(in view: UIView) -> [WKWebView] {
        (view as? WKWebView).map { [$0] } ?? view.subviews.flatMap { webViews(in: $0) }
    }

    @MainActor
    func testNativeStreamingToFinalKeepsWebViewAndReportsMeasuredHeight() async throws {
        let content = Content()
        let host = UIHostingController(rootView: Host(content: content))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 350, height: 800))
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene { window.windowScene = scene }
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        host.view.layoutIfNeeded()
        let web = try XCTUnwrap(webViews(in: host.view).first)
        for _ in 0..<100 {
            if (try? await evaluate("String(Boolean(document.querySelector('h1')))", in: web)) == "true" { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        _ = try await evaluate("window.originalHeading = document.querySelector('h1'); 'ok'", in: web)
        content.text = "# Title\n\nGrowing final text"
        content.streaming = false
        for _ in 0..<100 {
            if (try? await evaluate("String(document.querySelector('p')?.textContent)", in: web)) == "Growing final text" { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(webViews(in: host.view).count, 1)
        XCTAssertTrue(webViews(in: host.view).first === web)
        let stable = try await evaluate("String(originalHeading === document.querySelector('h1'))", in: web)
        XCTAssertEqual(stable, "true")
        XCTAssertGreaterThan(web.frame.height, 30)
    }

    @MainActor
    private final class ShiftRecorder: NSObject, WKScriptMessageHandler {
        var shifts: [Double] = []
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if let value = message.body as? NSNumber { shifts.append(value.doubleValue) }
        }
    }

    @MainActor
    func testReadingAnchorReportsLayoutShiftAboveVisibleParagraph() async throws {
        let web = try await renderer()
        let host = UIViewController()
        host.view.addSubview(web)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 350, height: 800))
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene { window.windowScene = scene }
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        host.view.layoutIfNeeded()
        let recorder = ShiftRecorder()
        web.configuration.userContentController.add(recorder, name: "readingShift")
        defer { web.configuration.userContentController.removeScriptMessageHandler(forName: "readingShift") }
        try await render("First paragraph.\n\nVisible paragraph.", streaming: false, in: web)
        try await Task.sleep(for: .milliseconds(200))
        _ = try await evaluate("const visible = document.querySelectorAll('p')[1]; window.FamiliarMarkdown.setReadingTop(visible.getBoundingClientRect().top + 2); document.querySelector('p').style.height = '250px'; 'ok'", in: web)
        for _ in 0..<60 {
            if !recorder.shifts.isEmpty { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertGreaterThan(try XCTUnwrap(recorder.shifts.first), 100)
    }

    @MainActor
    private func renderer() async throws -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 350, height: 800), configuration: configuration)
        web.loadHTMLString(FamiliarMarkdownHTML.baseDocument, baseURL: FamiliarMarkdownHTML.rendererDirectory())
        for _ in 0..<120 {
            if (try? await evaluate("String(typeof window.FamiliarMarkdown)", in: web)) == "object" { return web }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw NSError(domain: "RendererDidNotLoad", code: 1)
    }

    @MainActor
    private func evaluate(_ script: String, in web: WKWebView) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            web.evaluateJavaScript(script) { result, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: result as? String ?? "") }
            }
        }
    }

    @MainActor
    private func render(_ markdown: String, streaming: Bool, in web: WKWebView) async throws {
        let literal = FamiliarMarkdownHTML.javascriptStringLiteral(markdown)
        _ = try await evaluate("window.FamiliarMarkdown.render(\(literal), {streaming: \(streaming), reduceMotion: false}); 'ok'", in: web)
    }

    @MainActor
    func testGrowingTextAndFinalRenderReuseBlocksAndHeadingNodes() async throws {
        let web = try await renderer()
        try await render("# Title\n\nGrowing", streaming: true, in: web)
        _ = try await evaluate("window.originalHeading = document.querySelector('h1'); window.originalParagraph = document.querySelector('p'); window.originalBlock = document.querySelectorAll('.markdown-block')[1]; 'ok'", in: web)
        try await render("# Title\n\nGrowing text 👨‍👩‍👧‍👦\n\n- First\n- Second", streaming: true, in: web)
        let growing = try await evaluate("JSON.stringify([originalHeading === document.querySelector('h1'), originalParagraph === document.querySelector('p'), originalBlock === document.querySelectorAll('.markdown-block')[1], document.querySelector('p').textContent])", in: web)
        XCTAssertEqual(growing, "[true,true,true,\"Growing text 👨‍👩‍👧‍👦\"]")
        try await render("# Title\n\nGrowing text 👨‍👩‍👧‍👦\n\n- First\n- Second", streaming: false, in: web)
        let final = try await evaluate("JSON.stringify([originalHeading === document.querySelector('h1'), originalParagraph === document.querySelector('p'), !document.getElementById('content').classList.contains('streaming')])", in: web)
        XCTAssertEqual(final, "[true,true,true]")
    }

    @MainActor
    func testComplexBlocksAndUnsafeMarkupStayBoundedAndLocal() async throws {
        let web = try await renderer()
        let markdown = "# Code\n\n~~~swift\nlet value = 1\n~~~\n\n| A | B |\n|---|---|\n| 1 | 2 |\n\n<script>alert(1)</script>\n\n[bad](javascript:alert(1))"
        try await render(markdown, streaming: true, in: web)
        _ = try await evaluate("window.codeBlock = document.querySelectorAll('.markdown-block')[1]; 'ok'", in: web)
        try await render(markdown + "\n\nDone", streaming: false, in: web)
        let result = try await evaluate("JSON.stringify([codeBlock === document.querySelectorAll('.markdown-block')[1], document.querySelectorAll('.code-block').length, document.querySelectorAll('.table-scroll').length, document.querySelectorAll('#content script, #content a[href^=javascript]').length])", in: web)
        XCTAssertEqual(result, "[true,1,1,0]")
    }

    @MainActor
    func testOpenFenceCompletesWithoutReplacingCodeContainer() async throws {
        let web = try await renderer()
        try await render("~~~swift\nlet value = 1", streaming: true, in: web)
        _ = try await evaluate("window.originalPre = document.querySelector('pre'); window.originalCode = document.querySelector('pre code'); window.originalContainer = document.querySelector('.code-block'); 'ok'", in: web)
        let open = try await evaluate("String(document.querySelector('.copy-code').disabled)", in: web)
        XCTAssertEqual(open, "true")
        try await render("~~~swift\nlet value = 123\n~~~", streaming: false, in: web)
        let final = try await evaluate("JSON.stringify([originalPre === document.querySelector('pre'), originalCode === document.querySelector('pre code'), originalContainer === document.querySelector('.code-block'), document.querySelector('.copy-code').disabled, document.querySelector('pre code').textContent.trim()])", in: web)
        XCTAssertEqual(final, "[true,true,true,false,\"let value = 123\"]")
    }

    @MainActor
    func testTableGrowthRetainsHorizontalScrollerAndCompletedPrefix() async throws {
        let web = try await renderer()
        let table = "| First column | Second column |\n|---|---|\n| Long text in the first column | Long text in the second column |"
        try await render("# Table\n\n" + table, streaming: true, in: web)
        _ = try await evaluate("window.originalTable = document.querySelector('table'); window.originalScroller = document.querySelector('.table-scroll'); originalScroller.style.width = '10px'; originalScroller.scrollLeft = 5; 'ok'", in: web)
        try await render("# Table\n\n" + table + "\n| Next row | More text |", streaming: true, in: web)
        let result = try await evaluate("JSON.stringify([originalTable === document.querySelector('table'), originalScroller === document.querySelector('.table-scroll'), originalScroller.scrollLeft])", in: web)
        XCTAssertEqual(result, "[true,true,5]")
    }
}
