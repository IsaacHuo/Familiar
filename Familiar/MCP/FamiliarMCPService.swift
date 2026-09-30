import Foundation
import SwiftData

@MainActor enum FamiliarMCPService {
    static func configurations(projectID: UUID?, conversationID: UUID, in context: ModelContext) throws -> [FamiliarMCPConfiguration] {
        let servers = try context.fetch(FetchDescriptor<FamiliarMCPServerRecord>())
        let bindings = try context.fetch(FetchDescriptor<FamiliarMCPBindingRecord>())
        return servers.compactMap { server in
            let conversationBinding = bindings.first { $0.serverID == server.id && $0.conversationID == conversationID }
            let projectBinding = bindings.first { $0.serverID == server.id && $0.projectID == projectID && $0.conversationID == nil && projectID != nil }
            guard conversationBinding?.enabled ?? projectBinding?.enabled ?? server.enabled,
                  let endpoint = URL(string: server.endpointString), endpoint.scheme == "https", endpoint.host != nil
            else { return nil }
            return .init(id: server.id, name: server.displayName, endpoint: endpoint, token: FamiliarKeychainStore.load(for: "mcp." + server.id.uuidString))
        }
    }

    struct Discovery {
        let tools: [AnyFamiliarTool]
        let unavailable: [FamiliarUnavailableTool]
    }
    static func snapshotTools(_ configurations: [FamiliarMCPConfiguration]) async throws -> Discovery {
        var tools: [AnyFamiliarTool] = []
        var unavailable: [FamiliarUnavailableTool] = []
        for configuration in configurations {
            let client = FamiliarMCPClient(configuration: configuration)
            do {
                let definitions = try await client.tools()
                tools += definitions.map { AnyFamiliarTool(FamiliarMCPTool(definition: $0, configuration: configuration, client: client)) }
            } catch {
                try Task.checkCancellation()
                unavailable.append(.init(name: "mcp_" + configuration.id.uuidString, title: configuration.name, reason: error.localizedDescription))
            }
        }
        return Discovery(tools: tools, unavailable: unavailable)
    }
}
