import Foundation

nonisolated enum FamiliarTerminalEvent: Sendable {
    case started
    case output(Data)
    case exited(Int32)
    case cancelled
    case failed(String)
}
