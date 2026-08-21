import Foundation
import SwiftData

@MainActor
struct FamiliarPinService {
    func all(in context: ModelContext) throws -> [FamiliarPinnedItemRecord] {
        try context.fetch(FetchDescriptor<FamiliarPinnedItemRecord>()).sorted {
            if $0.pinnedAt != $1.pinnedAt {
                return $0.pinnedAt > $1.pinnedAt
            }
            return $0.targetKey < $1.targetKey
        }
    }

    func isPinned(
        _ targetType: FamiliarPinnedTargetType,
        targetID: UUID,
        in context: ModelContext
    ) throws -> Bool {
        try record(targetType, targetID: targetID, in: context) != nil
    }

    @discardableResult
    func pin(
        _ targetType: FamiliarPinnedTargetType,
        targetID: UUID,
        pinnedAt: Date = Date(),
        in context: ModelContext
    ) throws -> FamiliarPinnedItemRecord {
        if let existing = try record(targetType, targetID: targetID, in: context) {
            return existing
        }

        let record = FamiliarPinnedItemRecord(
            targetType: targetType,
            targetID: targetID,
            pinnedAt: pinnedAt
        )
        context.insert(record)
        try save(context)
        return record
    }

    func unpin(
        _ targetType: FamiliarPinnedTargetType,
        targetID: UUID,
        in context: ModelContext
    ) throws {
        guard let record = try record(targetType, targetID: targetID, in: context) else { return }
        context.delete(record)
        try save(context)
    }

    @discardableResult
    func toggle(
        _ targetType: FamiliarPinnedTargetType,
        targetID: UUID,
        pinnedAt: Date = Date(),
        in context: ModelContext
    ) throws -> Bool {
        if let record = try record(targetType, targetID: targetID, in: context) {
            context.delete(record)
            try save(context)
            return false
        }

        context.insert(FamiliarPinnedItemRecord(
            targetType: targetType,
            targetID: targetID,
            pinnedAt: pinnedAt
        ))
        try save(context)
        return true
    }

    @discardableResult
    func removePins(
        _ targetType: FamiliarPinnedTargetType,
        targetIDs: Set<UUID>,
        in context: ModelContext
    ) throws -> Int {
        let count = try stageRemoval(targetType, targetIDs: targetIDs, in: context)
        guard count > 0 else { return 0 }
        try save(context)
        return count
    }

    @discardableResult
    func stageRemoval(
        _ targetType: FamiliarPinnedTargetType,
        targetIDs: Set<UUID>,
        in context: ModelContext
    ) throws -> Int {
        guard !targetIDs.isEmpty else { return 0 }
        let rawValue = targetType.rawValue
        let candidates = try context.fetch(FetchDescriptor<FamiliarPinnedItemRecord>(
            predicate: #Predicate { $0.targetTypeRawValue == rawValue }
        ))
        let records = candidates.filter { targetIDs.contains($0.targetID) }
        guard !records.isEmpty else { return 0 }

        records.forEach(context.delete)
        return records.count
    }

    private func record(
        _ targetType: FamiliarPinnedTargetType,
        targetID: UUID,
        in context: ModelContext
    ) throws -> FamiliarPinnedItemRecord? {
        let targetKey = targetType.targetKey(for: targetID)
        var descriptor = FetchDescriptor<FamiliarPinnedItemRecord>(
            predicate: #Predicate { $0.targetKey == targetKey }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func save(_ context: ModelContext) throws {
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }
}
