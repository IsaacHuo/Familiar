import SwiftData

/// Keep SQLite IN parameters bounded even for a conversation with many Runs.
/// The descriptor owns its real predicate; this helper never fetches all rows.
enum FamiliarRunHistoryQuery {
    static func fetch<Record: PersistentModel>(_ runtimeIDs: [String], in context: ModelContext,
        descriptor: ([String]) -> FetchDescriptor<Record>) throws -> [Record] {
        let ids = Array(Set(runtimeIDs)).sorted()
        var result: [Record] = []
        for start in stride(from: 0, to: ids.count, by: 200) {
            let batch = Array(ids[start..<min(start + 200, ids.count)])
            result += try context.fetch(descriptor(batch))
        }
        return result
    }
}
