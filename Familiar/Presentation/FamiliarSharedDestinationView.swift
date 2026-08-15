import SwiftData
import SwiftUI

enum FamiliarSharedDestination {
    case project(FamiliarProject)
    case ordinary
}

struct FamiliarSharedDestinationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(
        filter: #Predicate<FamiliarProject> { $0.statusRawValue == "active" },
        sort: \FamiliarProject.updatedAt,
        order: .reverse
    ) private var projects: [FamiliarProject]

    let onSelect: (FamiliarSharedDestination) -> Void
    @State private var newProjectName = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section(String(localized: "share.destination.project", defaultValue: "加入项目")) {
                    ForEach(projects) { project in
                        Button {
                            onSelect(.project(project))
                        } label: {
                            HStack {
                                Text(project.name).foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                            }
                        }
                    }
                    if projects.isEmpty {
                        Text(String(localized: "project.empty.title"))
                            .foregroundStyle(.secondary)
                    }
                }

                Section(String(localized: "share.destination.new_project", defaultValue: "新建项目")) {
                    TextField(String(localized: "project.name"), text: $newProjectName)
                    Button(String(localized: "project.create")) {
                        do {
                            let project = try FamiliarProjectService().create(name: newProjectName, in: modelContext)
                            onSelect(.project(project))
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                    .disabled(newProjectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                Section {
                    Button(String(localized: "share.destination.ordinary", defaultValue: "作为普通聊天草稿")) {
                        onSelect(.ordinary)
                    }
                }
            }
            .navigationTitle(String(localized: "share.destination.title", defaultValue: "选择目标"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.cancel")) { dismiss() }
                }
            }
            .alert(String(localized: "app.name"), isPresented: Binding(
                get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
            )) {
                Button(String(localized: "common.ok"), role: .cancel) {}
            } message: {
                Text(errorMessage ?? String(localized: "error.unknown"))
            }
        }
    }
}
