import SwiftUI
import SwiftData

struct FamiliarMCPSettingsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \FamiliarMCPServerRecord.displayName) private var servers: [FamiliarMCPServerRecord]
    @Query private var bindings: [FamiliarMCPBindingRecord]
    var projectID: UUID? = nil
    var conversationID: UUID? = nil
    @State private var editing: Editor?
    @State private var errorMessage: String?
    @State private var importJSON = ""
    @State private var showsImport = false

    private struct Editor: Identifiable { let id: UUID; let server: FamiliarMCPServerRecord? }
    var body: some View {
        List {
            Section {
                ForEach(servers) { server in
                    HStack {
                        Button { editing = .init(id: server.id, server: server) } label: {
                            HStack(spacing: FamiliarSpacing.small) {
                                VStack(alignment: .leading, spacing: FamiliarSpacing.xSmall) {
                                    Text(server.displayName)
                                    Text(server.endpointString).font(FamiliarTypography.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer(minLength: FamiliarSpacing.small)
                                Image(systemName: "chevron.right")
                                    .font(FamiliarTypography.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                                    .accessibilityHidden(true)
                            }
                            .frame(maxWidth: .infinity, minHeight: FamiliarControlSize.minimumHitTarget, alignment: .leading)
                        }
                        Toggle(server.displayName, isOn: enabledBinding(server)).labelsHidden()
                    }
                }
            } footer: { Text(String(localized: "mcp.scope.footer")) }
            Button { editing = .init(id: UUID(), server: nil) } label: { Text(String(localized: "mcp.add")) }
            Button(String(localized: "mcp.import")) { showsImport = true }
        }
        .navigationTitle(String(localized: "mcp.title"))
        .sheet(item: $editing) { editor in
            FamiliarMCPServerEditor(server: editor.server, identifier: editor.id)
        }
        .sheet(isPresented: $showsImport) {
            NavigationStack {
                Form { TextEditor(text: $importJSON).font(FamiliarTypography.body.monospaced()).frame(minHeight: 240) }
                    .navigationTitle(String(localized: "mcp.import"))
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button(String(localized: "common.cancel")) { showsImport = false } }
                        ToolbarItem(placement: .confirmationAction) { Button(String(localized: "common.save")) { importServers() } }
                    }
            }
        }
        .alert(String(localized: "settings.error.title"), isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button(String(localized: "common.ok"), role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
    }
    private func enabledBinding(_ server: FamiliarMCPServerRecord) -> Binding<Bool> {
        let binding = bindings.first { $0.serverID == server.id && $0.projectID == projectID && $0.conversationID == conversationID }
        return Binding(get: { binding?.enabled ?? server.enabled }, set: { enabled in
            if projectID == nil && conversationID == nil { server.enabled = enabled }
            else if let binding { binding.enabled = enabled; binding.updatedAt = Date() }
            else { context.insert(FamiliarMCPBindingRecord(serverID: server.id, projectID: projectID, conversationID: conversationID, enabled: enabled)) }
            do { try context.save() } catch { context.rollback(); errorMessage = error.localizedDescription }
        })
    }
    private func importServers() {
        do {
            guard let root = try JSONSerialization.jsonObject(with: Data(importJSON.utf8)) as? [String: Any],
                  let items = root["mcpServers"] as? [String: [String: Any]], !items.isEmpty else { throw FamiliarMCPError.invalidResponse }
            // Validate the complete import before inserting anything.
            var values: [(String, URL)] = []
            for (name, item) in items {
                guard item["command"] == nil, item["headers"] == nil, item["oauth"] == nil,
                      let raw = item["url"] as? String, let url = URL(string: raw), url.scheme == "https", url.host != nil,
                      url.user == nil, url.password == nil else { throw FamiliarMCPError.server(String(localized: "mcp.import.unsupported")) }
                values.append((name, url))
            }
            for (name, url) in values {
                context.insert(FamiliarMCPServerRecord(displayName: name, endpointString: url.absoluteString, serverIdentity: UUID().uuidString))
            }
            try context.save(); showsImport = false; importJSON = ""
        } catch { context.rollback(); errorMessage = error.localizedDescription }
    }
}

private struct FamiliarMCPServerEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let server: FamiliarMCPServerRecord?
    let identifier: UUID
    @State private var name = ""
    @State private var endpoint = ""
    @State private var token = ""
    @State private var toolNames: [String] = []
    @State private var busy = false
    @State private var errorMessage: String?
    @State private var confirmsDelete = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(String(localized: "provider.name"), text: $name)
                    TextField(String(localized: "mcp.endpoint"), text: $endpoint).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    SecureField(String(localized: "mcp.token"), text: $token).textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                Button(String(localized: "mcp.discover")) { discover() }.disabled(busy)
                if busy { ProgressView() }
                ForEach(toolNames, id: \.self) { Text($0) }
                if server != nil {
                    Button(String(localized: "common.delete"), role: .destructive) { confirmsDelete = true }
                }
            }
            .navigationTitle(String(localized: "mcp.server"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(String(localized: "common.cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(String(localized: "common.save")) { save() }.disabled(busy) }
            }
            .onAppear { name = server?.displayName ?? ""; endpoint = server?.endpointString ?? "" }
            .alert(String(localized: "settings.error.title"), isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button(String(localized: "common.ok"), role: .cancel) {}
            } message: { Text(errorMessage ?? "") }
            .confirmationDialog(String(localized: "common.delete"), isPresented: $confirmsDelete) {
                Button(String(localized: "common.delete"), role: .destructive) {
                    guard let server else { return }
                    do {
                        let id = server.id
                        for binding in try context.fetch(FetchDescriptor<FamiliarMCPBindingRecord>(predicate: #Predicate { $0.serverID == id })) { context.delete(binding) }
                        context.delete(server); try context.save()
                        try FamiliarKeychainStore.delete(for: "mcp." + identifier.uuidString)
                        dismiss()
                    } catch { context.rollback(); errorMessage = error.localizedDescription }
                }
            }
        }
    }
    private func configuration() throws -> FamiliarMCPConfiguration {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let url = URL(string: endpoint), url.scheme == "https", url.host != nil, url.user == nil, url.password == nil, url.fragment == nil else { throw FamiliarMCPError.invalidResponse }
        return .init(id: identifier, name: name, endpoint: url, token: token.isEmpty ? FamiliarKeychainStore.load(for: "mcp." + identifier.uuidString) : token)
    }
    private func discover() {
        do {
            let config = try configuration(); busy = true
            Task { @MainActor in
                defer { busy = false }
                do { toolNames = try await FamiliarMCPClient(configuration: config).tools().map(\.name) }
                catch { errorMessage = error.localizedDescription }
            }
        } catch { errorMessage = error.localizedDescription }
    }
    private func save() {
        do {
            let config = try configuration()
            let value = server ?? FamiliarMCPServerRecord(displayName: name, endpointString: config.endpoint.absoluteString, serverIdentity: identifier.uuidString, id: identifier)
            value.displayName = name; value.endpointString = config.endpoint.absoluteString; value.updatedAt = Date()
            if server == nil { context.insert(value) }
            try context.save()
            if !token.isEmpty { try FamiliarKeychainStore.save(token, for: "mcp." + identifier.uuidString) }
            dismiss()
        } catch { context.rollback(); errorMessage = error.localizedDescription }
    }
}
