import Foundation
import SwiftData
import Testing
@testable import Familiar

@Suite("Persistent pins")
struct FamiliarPinServiceTests {
    @Test("Pin is idempotent and all returns newest pins first")
    @MainActor
    func pinIsIdempotentAndOrdered() throws {
        let container = try FamiliarTestStore.make(name: "PinIdempotency")
        let context = container.mainContext
        let service = FamiliarPinService()
        let conversationID = UUID()
        let projectID = UUID()
        let earlier = Date(timeIntervalSince1970: 100)
        let later = Date(timeIntervalSince1970: 200)

        let original = try service.pin(.conversation, targetID: conversationID, pinnedAt: earlier, in: context)
        let duplicate = try service.pin(.conversation, targetID: conversationID, pinnedAt: later, in: context)
        try service.pin(.project, targetID: projectID, pinnedAt: later, in: context)

        let pins = try service.all(in: context)
        #expect(pins.count == 2)
        #expect(pins.map(\.targetID) == [projectID, conversationID])
        #expect(original.targetKey == "conversation:\(conversationID.uuidString)")
        #expect(original.targetTypeRawValue == FamiliarPinnedTargetType.conversation.rawValue)
        #expect(original.targetType == .conversation)
        #expect(original.targetID == conversationID)
        #expect(duplicate.targetKey == original.targetKey)
        #expect(duplicate.pinnedAt == earlier)
        #expect(try service.isPinned(.conversation, targetID: conversationID, in: context))
        #expect(try service.isPinned(.project, targetID: projectID, in: context))
    }

    @Test("Toggle, unpin, and target ID cleanup affect only matching pins")
    @MainActor
    func mutationsAreScopedToTypeAndTargetIDs() throws {
        let container = try FamiliarTestStore.make(name: "PinMutations")
        let context = container.mainContext
        let service = FamiliarPinService()
        let removedConversationID = UUID()
        let retainedConversationID = UUID()
        let sharedID = UUID()

        #expect(try service.toggle(.conversation, targetID: removedConversationID, in: context))
        #expect(try !service.toggle(.conversation, targetID: removedConversationID, in: context))
        #expect(try !service.isPinned(.conversation, targetID: removedConversationID, in: context))

        try service.pin(.conversation, targetID: removedConversationID, in: context)
        try service.pin(.conversation, targetID: retainedConversationID, in: context)
        try service.pin(.conversation, targetID: sharedID, in: context)
        try service.pin(.project, targetID: sharedID, in: context)

        let removedCount = try service.removePins(
            .conversation,
            targetIDs: [removedConversationID, sharedID],
            in: context
        )
        #expect(removedCount == 2)
        #expect(try service.isPinned(.conversation, targetID: retainedConversationID, in: context))
        #expect(try !service.isPinned(.conversation, targetID: sharedID, in: context))
        #expect(try service.isPinned(.project, targetID: sharedID, in: context))

        try service.unpin(.project, targetID: sharedID, in: context)
        try service.unpin(.project, targetID: sharedID, in: context)
        #expect(try service.all(in: context).map(\.targetID) == [retainedConversationID])
    }
}
