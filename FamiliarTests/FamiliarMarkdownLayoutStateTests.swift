import CoreGraphics
import Testing
@testable import Familiar

@Suite("Rich message initial layout")
struct FamiliarMarkdownLayoutStateTests {
    @Test("The measured height and placeholder handoff publish together and stay ready during reflow")
    func measuredHandoff() {
        var layout = FamiliarMarkdownLayoutState()
        layout.receive(1) // The empty bootstrap document is not message content.
        #expect(layout.height == 1 && !layout.isMeasured)
        layout.receive(240)
        #expect(layout.height == 240 && layout.isMeasured)
        layout.receive(180) // Code, fonts or width may settle to a different height.
        #expect(layout.height == 180 && layout.isMeasured)
        let measured = layout
        for invalid in [CGFloat.nan, .infinity, 0, -1] { layout.receive(invalid) }
        #expect(layout == measured)
        layout.receive(1) // An emptied message does not replay the placeholder.
        #expect(layout.height == 1 && layout.isMeasured)
    }
}
