import Foundation
import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import Familiar

@Suite("Telegram motion and file operation contracts", .serialized)
@MainActor struct FamiliarTelegramMotionTests {
    @Test("Chat and preview attachment ordering preserves IDs and gives status to the final displayed item")
    func attachmentPresentation() {
        func attachment(_ kind: FamiliarAttachmentKind) -> FamiliarAttachmentSnapshot {
            .init(id: UUID(), kind: kind, filename: "fixture", mimeType: "application/octet-stream",
                relativePath: "fixture", extractedText: "", byteSize: 4, extractionEngine: "test",
                extractionVersion: "1", detectedFormat: "txt", usedOCR: false)
        }
        let document = attachment(.document), first = attachment(.image), last = attachment(.image)
        let plain = FamiliarMessageAttachmentPresentation(attachments: [first, document, last], hasCaption: false)
        #expect(plain.attachments.map(\.id) == [first.id, last.id, document.id])
        #expect(plain.statusAttachmentID == document.id)
        #expect(plain.neighbors(for: first.id) == .init(top: false, bottom: true))
        #expect(plain.neighbors(for: last.id) == .init(top: true, bottom: true))
        #expect(plain.neighbors(for: document.id) == .init(top: true, bottom: false))
        let caption = FamiliarMessageAttachmentPresentation(attachments: [first, document, last], hasCaption: true, neighbors: .init(bottom: true))
        #expect(caption.statusAttachmentID == nil)
        #expect(caption.captionNeighbors == .init(top: true, bottom: true))
        #expect(caption.neighbors(for: document.id) == .init(top: true, bottom: true))
        let images = FamiliarMessageAttachmentPresentation(attachments: [first, last], hasCaption: false)
        #expect(images.statusAttachmentID == last.id)
        #expect(!images.hasContentAbove(first.id) && !images.hasContentBelow(last.id))
    }

    @Test("A queued menu action cannot survive changed message, block, text or eligibility")
    func staleContextMenu() throws {
        for change in 0..<4 {
            let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let window = UIWindow(windowScene: scene)
            window.frame = .init(x: 0, y: 0, width: 320, height: 640)
            let controller = UIViewController()
            window.rootViewController = controller; window.isHidden = false
            defer { window.isHidden = true }
            let textView = UITextView(frame: .init(x: 0, y: 0, width: 300, height: 100))
            controller.view.addSubview(textView)
            let bridge = FamiliarMessageInteraction(), scroll = FamiliarChatScrollSession()
            bridge.scroll = scroll; bridge.attach(to: textView)
            defer { bridge.detach() }
            let messageID = UUID()
            var edits = 0
            bridge.actions = .init(text: "Original", messageID: messageID, blockID: "first", edit: { edits += 1 })
            let interaction = try #require(textView.interactions.compactMap { $0 as? UIContextMenuInteraction }.first)
            let configuration = try #require(bridge.contextMenuInteraction(interaction, configurationForMenuAtLocation: .zero))
            let menuID = try #require(configuration.identifier as? UUID)
            let menu = try #require(bridge.makeContextMenu(id: menuID))
            let edit = try #require(menu.children.compactMap { $0 as? UIAction }.first { $0.title == String(localized: "common.edit") })
            bridge.contextMenuInteraction(interaction, willDisplayMenuFor: configuration, animator: nil)
            #expect(scroll.isInspecting)
            let button = UIButton(); button.addAction(edit, for: .touchUpInside); button.sendActions(for: .touchUpInside)
            let animator = FamiliarDeferredMenuAnimator()
            bridge.contextMenuInteraction(interaction, willEndFor: configuration, animator: animator)
            #expect(edits == 0)
            bridge.actions = .init(text: change == 2 ? "Updated" : "Original",
                messageID: change == 0 ? UUID() : messageID, blockID: change == 1 ? "second" : "first",
                edit: change == 3 ? nil : { edits += 1 })
            animator.complete()
            #expect(edits == 0 && !scroll.isInspecting)
        }
    }

    @Test("A detached menu completion cannot run after reattachment; a current action runs once after dismissal")
    func menuAttachmentLifetime() throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = .init(x: 0, y: 0, width: 320, height: 640)
        let controller = UIViewController(); window.rootViewController = controller; window.isHidden = false
        defer { window.isHidden = true }
        let textView = UITextView(frame: .init(x: 0, y: 0, width: 300, height: 100))
        controller.view.addSubview(textView)
        let bridge = FamiliarMessageInteraction()
        var edits = 0
        bridge.actions = .init(text: "Original", messageID: UUID(), edit: { edits += 1 })
        func queue() throws -> (UIContextMenuInteraction, UIContextMenuConfiguration) {
            let interaction = try #require(textView.interactions.compactMap { $0 as? UIContextMenuInteraction }.first)
            let configuration = try #require(bridge.contextMenuInteraction(interaction, configurationForMenuAtLocation: .zero))
            let menuID = try #require(configuration.identifier as? UUID)
            let menu = try #require(bridge.makeContextMenu(id: menuID))
            let edit = try #require(menu.children.compactMap { $0 as? UIAction }.first { $0.title == String(localized: "common.edit") })
            let button = UIButton(); button.addAction(edit, for: .touchUpInside); button.sendActions(for: .touchUpInside)
            return (interaction, configuration)
        }
        bridge.attach(to: textView)
        let old = try queue(), animator = FamiliarDeferredMenuAnimator()
        bridge.contextMenuInteraction(old.0, willEndFor: old.1, animator: animator)
        bridge.detach(); bridge.attach(to: textView)
        defer { bridge.detach() }
        let current = try queue()
        animator.complete()
        #expect(edits == 0)
        bridge.contextMenuInteraction(current.0, willEndFor: current.1, animator: nil)
        bridge.contextMenuInteraction(current.0, willEndFor: current.1, animator: nil)
        #expect(edits == 1)
        let superseded = try queue()
        let replacement = try #require(bridge.contextMenuInteraction(superseded.0, configurationForMenuAtLocation: .zero))
        #expect(bridge.makeContextMenu(id: try #require(superseded.1.identifier as? UUID)) == nil)
        bridge.contextMenuInteraction(superseded.0, willEndFor: superseded.1, animator: nil)
        bridge.contextMenuInteraction(superseded.0, willEndFor: replacement, animator: nil)
        #expect(edits == 1)
    }

    @Test("Bubble stretching preserves opaque content corners for tall and wide messages")
    func bubbleStretchGeometry() throws {
        for outgoing in [false, true] {
            for neighbors in [FamiliarMessageNeighbors(), .init(top: true), .init(bottom: true), .init(top: true, bottom: true)] {
                for size in [CGSize(width: 300, height: 800), CGSize(width: 300, height: 44)] {
                    let renderer = ImageRenderer(content: FamiliarMessageBubbleBackground(isUser: outgoing)
                        .environment(\.familiarMessageNeighbors, neighbors)
                        .environment(\.colorScheme, .light)
                        .environment(\.displayScale, 2)
                        .frame(width: size.width, height: size.height))
                    renderer.scale = 2
                    let image = try #require(renderer.cgImage)
                    let width = image.width, height = image.height
                    var pixels = [UInt8](repeating: 0, count: width * height * 4)
                    try pixels.withUnsafeMutableBytes { buffer in
                        let context = try #require(CGContext(data: buffer.baseAddress, width: width, height: height,
                            bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
                        context.draw(image, in: .init(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
                    }
                    // An ellipse leaves these text-inset corners transparent.
                    for x in [24, Int(size.width) - 24] {
                        for y in [12, Int(size.height) - 12] {
                            #expect(pixels[((y * 2) * width + x * 2) * 4 + 3] > 240)
                        }
                    }
                    #expect(pixels[3] == 0)
                }
            }
        }
    }

    @Test("Media viewports fit their parent and bound extreme image ratios")
    func mediaViewportGeometry() {
        let landscape = FamiliarChatImageLayout(nativeSize: .init(width: 1_600, height: 900)).size(availableWidth: 340)
        #expect(landscape == .init(width: 300, height: 168.75))
        let portrait = FamiliarChatImageLayout(nativeSize: .init(width: 1_000, height: 2_000)).size(availableWidth: 340)
        #expect(portrait == .init(width: 190, height: 380))
        let panorama = FamiliarChatImageLayout(nativeSize: .init(width: 10_000, height: 1_000)).size(availableWidth: 340)
        #expect(panorama == .init(width: 300, height: 74))
        let tall = FamiliarChatImageLayout(nativeSize: .init(width: 1_000, height: 10_000)).size(availableWidth: 120)
        #expect(tall == .init(width: 120, height: 380))
    }

    @Test("Mixed-direction final lines keep timestamps out of RTL glyph runs")
    func timestampDirection() {
        #expect(FamiliarMessageReadingStyle.hasRightToLeftRun("English مرحبا"))
        #expect(FamiliarMessageReadingStyle.hasRightToLeftRun("שלום 123"))
        #expect(!FamiliarMessageReadingStyle.hasRightToLeftRun("English 123 👩🏽‍💻"))
        #expect(!FamiliarMessageReadingStyle.hasRightToLeftRun("中文"))
    }

    @Test("Multiline messages reserve only a trailing status width and keep a width-only text proposal")
    func trailingStatusGeometry() {
        let inline = FamiliarTextAndTimeLayout.Measurement(
            textSize: .init(width: 140, height: 60), timeSize: .init(width: 32, height: 13),
            availableWidth: 160, lastLineWidth: 80, requiresSeparateLine: false)
        #expect(inline.isInline && inline.size == .init(width: 140, height: 60))
        #expect(inline.textProposal.width == 160 && inline.textProposal.height == nil)
        let newRow = FamiliarTextAndTimeLayout.Measurement(
            textSize: .init(width: 140, height: 60), timeSize: .init(width: 32, height: 13),
            availableWidth: 160, lastLineWidth: 130, requiresSeparateLine: false)
        #expect(!newRow.isInline && newRow.size == .init(width: 140, height: 77))
        let wideClock = FamiliarTextAndTimeLayout.Measurement(
            textSize: .init(width: 60, height: 20), timeSize: .init(width: 80, height: 13),
            availableWidth: 160, lastLineWidth: 60, requiresSeparateLine: false)
        #expect(wideClock.isInline && wideClock.size == .init(width: 148, height: 20))
    }

    @Test("RTL and explicit final empty lines always reserve their status row")
    func standaloneStatusGeometry() {
        for text in ["English مرحبا", "שלום 123"] {
            let measurement = FamiliarTextAndTimeLayout.Measurement(
                textSize: .init(width: 90, height: 20), timeSize: .init(width: 32, height: 13),
                availableWidth: 300, lastLineWidth: 30,
                requiresSeparateLine: FamiliarMessageReadingStyle.hasRightToLeftRun(text))
            #expect(!measurement.isInline && measurement.size.height == 37)
        }
        let finalEmptyLine = FamiliarTextAndTimeLayout.Measurement(
            textSize: .init(width: 90, height: 60), timeSize: .init(width: 32, height: 13),
            availableWidth: 300, lastLineWidth: 0, requiresSeparateLine: true)
        #expect(!finalEmptyLine.isInline && finalEmptyLine.size.height == 77)
    }

    @Test("Batch delete preserves failed items and rejects scope changes")
    func batchDeleteScopeAndFailure() async throws {
        let container = try FamiliarModelContainer.makeInMemory(), context = container.mainContext
        let scope = FamiliarWorkScope.conversation(UUID())
        let first = FamiliarFileRecord(scope: scope, displayName: "First", origin: .generated)
        let failed = FamiliarFileRecord(scope: scope, displayName: "Failed", origin: .upload)
        let moved = FamiliarFileRecord(scope: .project(UUID()), displayName: "Moved", origin: .upload)
        for file in [first, failed, moved] { context.insert(file) }; try context.save()
        let firstID = first.id, failedID = failed.id, movedID = moved.id
        let targets = [first, failed, moved].map { FamiliarFileDeletionTarget(id: $0.id, scope: scope, name: $0.displayName) }
        let result = await FamiliarFileBatchDeletion.execute(targets, in: context) { file, context in
            if file.id == failedID { throw CocoaError(.fileWriteNoPermission) }
            try FamiliarFileCatalogService().delete(file, in: context)
        }
        #expect(result.succeeded == [firstID])
        #expect(Set(result.failures.keys) == [failedID, movedID])
        #expect(Set(try context.fetch(FetchDescriptor<FamiliarFileRecord>()).map(\.id)) == [failedID, movedID])
    }

    @Test("Selection appends without losing attachments or skills, and stale conversations cannot apply")
    func selectedTextDraftContract() {
        let controller = FamiliarChatController(dependencies: .init())
        controller.draft = "Original 😀"; let skill = UUID(); controller.selectedSkillID = skill
        let attachment = FamiliarAttachmentDraft(id: UUID(), kind: .document, filename: "keep.txt", mimeType: "text/plain", relativePath: "keep.txt", extractedText: "Evidence", byteSize: 8, extractionEngine: "test", extractionVersion: "1", detectedFormat: "txt", usedOCR: false)
        controller.draftAttachments = [attachment]
        #expect(!controller.appendSelectedText(.explain, text: "Passage", sourceID: UUID()))
        #expect(controller.draft == "Original 😀")
        #expect(controller.appendSelectedText(.shorten, text: "Passage 👩🏽‍💻", sourceID: controller.draftConversationID))
        #expect(controller.draft == "Original 😀\n\n" + FamiliarSelectionAction.shorten.prompt(for: "Passage 👩🏽‍💻"))
        #expect(controller.draftAttachments == [attachment] && controller.selectedSkillID == skill)
        #expect(controller.draftSelection == .caretAtEnd(of: controller.draft))
        #expect(!controller.isSending)
    }

    @Test("Only one message selection owns a timeline, including navigation teardown")
    func oneSelectionOwner() {
        let session = FamiliarChatScrollSession(), first = UUID(), second = UUID()
        var ended: [Int] = []
        session.beginMessageSelection(first) { ended.append(1) }
        session.beginMessageSelection(second) { ended.append(2) }
        #expect(ended == [1])
        session.endMessageSelection(first)
        session.setPresented(false)
        #expect(ended == [1, 2])
    }

    @Test("Gallery uses Telegram fade distances and its distance/velocity completion thresholds")
    func galleryDrag() {
        let halfway = FamiliarGalleryDrag(distance: 40, velocity: 0, height: 800)
        #expect(abs(halfway.controlsAlpha - 0.2) < 0.001 && halfway.backdropAlpha == 0.5)
        #expect(!halfway.shouldDismiss)
        #expect(!FamiliarGalleryDrag(distance: 200, velocity: 1_000, height: 800).shouldDismiss)
        #expect(FamiliarGalleryDrag(distance: -201, velocity: 0, height: 800).shouldDismiss)
        #expect(FamiliarGalleryDrag(distance: 0, velocity: -1_001, height: 800).shouldDismiss)
    }

    @Test("Profile mask progress clamps and blur/fade share the same source progress")
    func profileProgress() {
        #expect(FamiliarProfileCollapse(offset: -100).mask == 0)
        let middle = FamiliarProfileCollapse(offset: 60)
        #expect(middle.mask == 0.5)
        #expect(abs(middle.fade - 0.525) < 0.001 && abs(middle.blur - 0.45) < 0.001)
        #expect(FamiliarProfileCollapse(offset: 1_000).fade == 1)
        #expect(FamiliarProfileCollapse(offset: 1_000).blur == 1)
    }
}

@MainActor private final class FamiliarDeferredMenuAnimator: NSObject, UIContextMenuInteractionAnimating {
    var previewViewController: UIViewController? { nil }
    private var completions: [() -> Void] = []
    func addAnimations(_ animations: @escaping () -> Void) { animations() }
    func addCompletion(_ completion: @escaping () -> Void) { completions.append(completion) }
    func complete() { let pending = completions; completions = []; pending.forEach { $0() } }
}
