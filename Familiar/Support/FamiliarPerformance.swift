import os

/// Local Instruments intervals only. Never attach user content or credentials.
nonisolated enum FamiliarPerformance {
    private static let signposter = OSSignposter(subsystem: "com.isaachuo.familiar", category: .pointsOfInterest)

    struct Interval: Sendable {
        fileprivate let name: StaticString
        fileprivate let state: OSSignpostIntervalState?
        func end() {
            if let state { signposter.endInterval(name, state) }
        }
    }

    static func begin(_ name: StaticString) -> Interval {
        .init(name: name, state: signposter.isEnabled
            ? signposter.beginInterval(name, id: signposter.makeSignpostID()) : nil)
    }

    static func event(_ name: StaticString) {
        if signposter.isEnabled { signposter.emitEvent(name, id: signposter.makeSignpostID()) }
    }
}
