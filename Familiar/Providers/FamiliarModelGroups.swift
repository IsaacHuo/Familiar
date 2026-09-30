// Adapted from OpenMinis ModelGroup / ModelGroupRouter at 4ef2900 (GPL-3.0).
import Foundation

nonisolated struct FamiliarModelReference: Codable, Hashable, Sendable {
    let providerID: String
    let modelID: String
}
nonisolated struct FamiliarProviderRoute: Codable, Equatable, Sendable {
    let provider: FamiliarProviderDescriptor
    let modelID: String
}
nonisolated struct FamiliarModelGroup: Identifiable, Codable, Equatable, Sendable {
    var id: String = "group-" + UUID().uuidString
    var name: String
    var members: [FamiliarModelReference] = []
    var strategy: String = "fallback"
    var fallbackOnAnyError = false
}

nonisolated enum FamiliarModelGroupStore {
    private static let key = "familiar.model.groups.v1"
    static func load() -> [FamiliarModelGroup] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([FamiliarModelGroup].self, from: data)) ?? []
    }
    @MainActor static func save(_ group: FamiliarModelGroup) throws {
        guard !group.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !group.members.isEmpty,
              group.members.count <= 16, Set(group.members).count == group.members.count else { throw FamiliarProviderConnectionError.invalidResponse }
        var groups = load().filter { $0.id != group.id }; groups.append(group)
        UserDefaults.standard.set(try JSONEncoder().encode(groups), forKey: key)
    }
    @MainActor static func remove(_ id: String) throws {
        UserDefaults.standard.set(try JSONEncoder().encode(load().filter { $0.id != id }), forKey: key)
    }
    static func descriptors(instances: [FamiliarProviderDescriptor]) -> [FamiliarProviderDescriptor] {
        load().compactMap { group in
            let routes = group.members.compactMap { reference -> FamiliarProviderRoute? in
                guard let provider = instances.first(where: { $0.id == reference.providerID }), provider.curatedModels.contains(where: { $0.id == reference.modelID }) else { return nil }
                return .init(provider: provider, modelID: reference.modelID)
            }
            guard let first = routes.first else { return nil }
            let capabilities = routes.map { $0.provider.model(for: $0.modelID).capabilities }
            let model = FamiliarModelDescriptor(id: "group", displayName: group.name, capabilities: .init(
                supportsTools: capabilities.allSatisfy(\.supportsTools), supportsImages: capabilities.allSatisfy(\.supportsImages),
                supportsDocuments: capabilities.allSatisfy(\.supportsDocuments), maximumInputCharacters: capabilities.map(\.maximumInputCharacters).min() ?? 60_000
            ))
            return FamiliarProviderDescriptor(id: group.id, displayName: group.name, protocolKind: first.provider.protocolKind, baseURL: first.provider.baseURL, chatPath: first.provider.chatPath, modelsPath: nil, authStyle: first.provider.authStyle, additionalHeaders: [:], curatedModels: [model], openAIChat: first.provider.openAIChat, isCustom: false, routes: routes, routeStrategy: group.strategy, fallbackOnAnyError: group.fallbackOnAnyError)
        }
    }
}

nonisolated struct FamiliarGroupModelProvider: FamiliarModelProvider, Sendable {
    struct Member: Sendable { let provider: any FamiliarModelProvider; let modelID: String }
    let providerID: String
    let members: [Member]
    let strategy: String
    let fallbackOnAnyError: Bool
    let sessionID: String
    private let state = FamiliarGroupRouteState()

    func stream(request: FamiliarModelRequest) -> AsyncThrowingStream<FamiliarModelStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard !members.isEmpty else { throw FamiliarOAuthError.missingCredential }
                    let hash = FamiliarHash.sha256(sessionID)
                    let selected = Int(UInt64(hash.prefix(8), radix: 16) ?? 0) % members.count
                    let initial = await state.selectedIndex() ?? (strategy == "loadBalance" ? selected : 0)
                    let indices = strategy == "loadBalance" ? [initial] : Array(initial..<members.count) + Array(0..<initial)
                    for (position, index) in indices.enumerated() {
                        let member = members[index]
                        var emittedContent = false
                        do {
                            continuation.yield(.providerSelection(providerID: member.provider.providerID, modelID: member.modelID))
                            for try await event in member.provider.stream(request: .init(model: member.modelID, messages: request.messages, tools: request.tools)) {
                                try Task.checkCancellation()
                                switch event {
                                case .textDelta, .reasoningSummaryDelta, .toolCallDelta: emittedContent = true
                                default: break
                                }
                                continuation.yield(event)
                            }
                            await state.select(index)
                            continuation.finish(); return
                        } catch is CancellationError { throw CancellationError() }
                        catch {
                            let providerRejected: Bool
                            if case FamiliarProviderRequestError.server(_, let status, _) = error { providerRejected = [400, 401, 403, 404, 429].contains(status) }
                            else { providerRejected = error is FamiliarOAuthError }
                            guard !emittedContent, position + 1 < indices.count, fallbackOnAnyError || providerRejected else { throw error }
                        }
                    }
                    throw FamiliarOAuthError.missingCredential
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }
}
private actor FamiliarGroupRouteState {
    var index: Int?
    func selectedIndex() -> Int? { index }
    func select(_ value: Int) { index = value }
}
