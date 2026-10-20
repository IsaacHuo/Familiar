import SwiftData
import SwiftUI

struct FamiliarProjectTabsManager: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \FamiliarProject.createdAt) private var projects: [FamiliarProject]
    @AppStorage("familiar.project-tabs.order") private var order = ""
    @State private var editor: FamiliarProjectEditorDestination?
    @State private var errorMessage: String?
    private var active: [FamiliarProject] {
        let ids = order.split(separator: ",").map(String.init)
        return projects.filter { $0.status == .active }.sorted {
            let lhs = ids.firstIndex(of: $0.id.uuidString) ?? Int.max, rhs = ids.firstIndex(of: $1.id.uuidString) ?? Int.max
            if lhs != rhs { return lhs < rhs }
            return $0.createdAt == $1.createdAt ? $0.id.uuidString < $1.id.uuidString : $0.createdAt < $1.createdAt
        }
    }
    var body: some View {
        List {
            Section(String(localized: "chat.project_order")) {
                Text(String(localized: "chat.recent")).foregroundStyle(.secondary)
                ForEach(active) { project in projectLink(project) }
                    .onMove { indices, destination in
                        var ids = active.map(\.id)
                        ids.move(fromOffsets: indices, toOffset: destination)
                        order = ids.map(\.uuidString).joined(separator: ",")
                    }
            }
            if projects.contains(where: { $0.status == .archived }) {
                Section(String(localized: "project.archived")) {
                    ForEach(projects.filter { $0.status == .archived }) { project in projectLink(project) }
                }
            }
        }
        .navigationTitle(String(localized: "project.manage"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { EditButton() }
            ToolbarItem(placement: .topBarTrailing) {
                Button { editor = .create } label: { Image(systemName: "folder.badge.plus") }
                    .accessibilityLabel(String(localized: "project.create"))
                    .accessibilityIdentifier("projects.create")
            }
        }
        .sheet(item: $editor) { destination in FamiliarProjectEditorView(destination: destination) { project in
            var ids = order.split(separator: ",").map(String.init)
            if !ids.contains(project.id.uuidString) { ids.append(project.id.uuidString) }
            order = ids.joined(separator: ",")
        } }
        .alert(String(localized: "app.name"), isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button(String(localized: "common.ok"), role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
    }

    private func projectLink(_ project: FamiliarProject) -> some View {
        NavigationLink(value: FamiliarChatRoute.project(project.id)) {
            Label(project.displayName, systemImage: "folder")
        }
        .accessibilityIdentifier("project.open." + project.id.uuidString)
    }
}

struct FamiliarProjectDetailScreen: View {
    @Environment(\.modelContext) private var context
    let project: FamiliarProject
    let coordinator: FamiliarChatSessionCoordinator
    let onOpen: (UUID) -> Void
    let onNew: (UUID?) -> Void
    @State private var editor: FamiliarProjectEditorDestination?
    @State private var errorMessage: String?
    var body: some View {
        FamiliarProjectDetailView(project: project, registry: coordinator.dependencies.registry,
            onConversationRequest: { request in
                switch request { case .open(let id): onOpen(id); case .create(let id): onNew(id) }
            }, onDeleteConversations: { errorMessage = coordinator.deleteChats($0, in: context) },
            onEdit: { editor = .edit(project) }, onError: { errorMessage = $0 })
            .sheet(item: $editor) { destination in FamiliarProjectEditorView(destination: destination, onSave: { _ in }) }
            .alert(String(localized: "app.name"), isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button(String(localized: "common.ok"), role: .cancel) {}
            } message: { Text(errorMessage ?? "") }
    }
}
