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

    static func deferredGroups(_ configurations: [FamiliarMCPConfiguration]) -> [FamiliarDeferredToolGroup] {
        configurations.sorted { $0.id.uuidString < $1.id.uuidString }.map { configuration in
            .init(summary: .init(id: "mcp." + configuration.id.uuidString, title: configuration.name,
                                summary: "User-enabled remote server. Discover its tool directory, then select exact toolNames. All calls require approval."), discover: {
                let client = FamiliarMCPClient(configuration: configuration)
                let definitions = try await client.tools()
                try Task.checkCancellation()
                return definitions.map { AnyFamiliarTool(FamiliarMCPTool(definition: $0, configuration: configuration, client: client)) }
            })
        }
    }
}
