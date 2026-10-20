import Testing
import Foundation
import CoreGraphics
@testable import Familiar

@Suite("Chat reading ownership")
struct FamiliarChatScrollTests {
    @Test("The visible content block wins over its Turn and follows an expansion above it")
    @MainActor func contentBlockPriority() async throws {
        let session = FamiliarChatScrollSession()
        session.geometryChanged(offset: 200, latest: 500, viewport: 600)
        session.userBegan()
        session.rowChanged(id: "body", frame: .init(x: 0, y: -60, width: 300, height: 500), priority: 1) { _ in }
        session.rowChanged(id: "turn", frame: .init(x: 0, y: -300, width: 300, height: 1000)) { _ in }
        session.userEnded()
        var compensation: CGFloat = 0
        session.rowChanged(id: "body", frame: .init(x: 0, y: -20, width: 300, height: 500), priority: 1) { compensation = $0 }
        #expect(compensation == 0)
        try await Task.sleep(for: .milliseconds(20))
        #expect(compensation == 40)
    }

    @Test("Viewport motion and repeated geometry cannot create a counter-scroll loop")
    @MainActor func viewportMotionDoesNotCompensate() async throws {
        let session = FamiliarChatScrollSession()
        session.geometryChanged(offset: 200, latest: 500, viewport: 600)
        session.userBegan()
        session.rowChanged(id: "body", frame: .init(x: 0, y: -60, width: 300, height: 500)) { _ in }
        session.userEnded()
        var corrections: [CGFloat] = []
        // A stale row observation arrives before the matching viewport report.
        session.rowChanged(id: "body", frame: .init(x: 0, y: -100, width: 300, height: 500)) { corrections.append($0) }
        session.geometryChanged(offset: 240, latest: 500, viewport: 600)
        session.rowChanged(id: "body", frame: .init(x: 0, y: -100, width: 300, height: 500)) { corrections.append($0) }
        try await Task.sleep(for: .milliseconds(20))
        #expect(corrections.isEmpty)
        // Actual growth above the anchor is corrected once, after layout.
        session.rowChanged(id: "body", frame: .init(x: 0, y: -70, width: 300, height: 500)) { corrections.append($0) }
        session.rowChanged(id: "body", frame: .init(x: 0, y: -60, width: 300, height: 500)) { corrections.append($0) }
        try await Task.sleep(for: .milliseconds(20))
        #expect(corrections == [40])
        session.rowChanged(id: "body", frame: .init(x: 0, y: -60, width: 300, height: 500)) { corrections.append($0) }
        try await Task.sleep(for: .milliseconds(20))
        #expect(corrections == [40])
        session.geometryChanged(offset: 280, latest: 540, viewport: 600)
        session.rowChanged(id: "body", frame: .init(x: 0, y: -100, width: 300, height: 500)) { corrections.append($0) }
        try await Task.sleep(for: .milliseconds(20))
        #expect(corrections == [40])
    }

    @Test("Leaving a presentation cancels its queued reading correction")
    @MainActor func dismissCancelsCorrection() async throws {
        let session = FamiliarChatScrollSession(), presenter = UUID()
        session.beginPresentation(presenter)
        session.geometryChanged(offset: 200, latest: 500, viewport: 600, presenter: presenter)
        session.userBegan()
        session.rowChanged(id: "body", frame: .init(x: 0, y: -60, width: 300, height: 500), presenter: presenter) { _ in }
        session.userEnded()
        var moved = false
        session.rowChanged(id: "body", frame: .init(x: 0, y: -20, width: 300, height: 500), presenter: presenter) { _ in moved = true }
        session.endPresentation(presenter)
        try await Task.sleep(for: .milliseconds(20))
        #expect(!moved)
    }

    @Test("Internal Markdown shifts keep the row compensation baseline in sync")
    @MainActor func internalShift() async throws {
        let session = FamiliarChatScrollSession()
        session.geometryChanged(offset: 200, latest: 500, viewport: 600)
        session.userBegan()
        session.rowChanged(id: "reply", frame: CGRect(x: 0, y: -100, width: 300, height: 800)) { _ in }
        session.userEnded()
        session.contentShifted(75)
        var compensation: CGFloat = 0
        session.rowChanged(id: "reply", frame: CGRect(x: 0, y: -175, width: 300, height: 875)) { compensation = $0 }
        try await Task.sleep(for: .milliseconds(20))
        #expect(session.offset == 275)
        #expect(compensation == 0)
        #expect(session.mode == .userReading)
    }

    @Test("Content growth and keyboard changes cannot switch following into reading")
    func followingGeometry() {
        var state = FamiliarChatScrollState()
        state.geometryChanged(distance: 400)
        state.contentAdded()
        #expect(state.mode == .following)
        #expect(!state.showsReturnToLatest)
    }
    @Test("A user gesture immediately stops following, including near the bottom")
    func userOwnsReading() {
        var state = FamiliarChatScrollState()
        state.userBegan()
        state.geometryChanged(distance: 10)
        state.contentAdded()
        #expect(state.mode == .userReading)
        #expect(state.showsReturnToLatest)
        state.geometryChanged(distance: 500)
        state.userEnded()
        #expect(state.mode == .userReading)
        state.geometryChanged(distance: 0)
        #expect(state.mode == .userReading)
    }
    @Test("Return only finishes on reaching the bottom and a new gesture interrupts it")
    func explicitReturn() {
        var state = FamiliarChatScrollState()
        state.userBegan()
        state.geometryChanged(distance: 700)
        state.userEnded()
        state.requestReturn()
        state.geometryChanged(distance: 300)
        #expect(state.mode == .returnToLatest)
        state.userBegan()
        state.geometryChanged(distance: 0)
        #expect(state.mode == .userReading)
        state.userEnded()
        #expect(state.mode == .following)
        #expect(!state.showsReturnToLatest)
    }
}
