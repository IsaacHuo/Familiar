import SwiftUI

struct FamiliarModelGroupsView: View {
    let settings: FamiliarSettings
    let onSelect: (FamiliarSettings) -> Void
    @State private var groups = FamiliarModelGroupStore.load()
    @State private var editing: FamiliarModelGroup?
    @State private var errorMessage: String?
    var body: some View {
        List {
            ForEach(groups) { group in
                Button { editing = group } label: {
                    HStack {
                        Text(group.name).foregroundStyle(.primary)
                        Spacer()
                        if settings.providerID == group.id { Image(systemName: "checkmark") }
                        Text(group.members.count, format: .number).foregroundStyle(.secondary)
                    }.frame(minHeight: 44)
                }
            }
            .onDelete { offsets in
                do {
                    for index in offsets where groups[index].id != settings.providerID { try FamiliarModelGroupStore.remove(groups[index].id) }
                    groups = FamiliarModelGroupStore.load()
                } catch { errorMessage = error.localizedDescription }
            }
            Button { editing = .init(name: "") } label: { Label(String(localized: "group.add"), systemImage: "plus") }
        }
        .navigationTitle(String(localized: "group.title"))
        .sheet(item: $editing, onDismiss: { groups = FamiliarModelGroupStore.load() }) { group in
            FamiliarModelGroupEditor(group: group) { saved in
                var value = settings; value.providerID = saved.id; value.modelID = "group"; onSelect(value)
            }
        }
        .alert(String(localized: "settings.error.title"), isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button(String(localized: "common.ok"), role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
    }
}

private struct FamiliarModelGroupEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var group: FamiliarModelGroup
    let onSelect: (FamiliarModelGroup) -> Void
    @State private var errorMessage: String?
    var body: some View {
        NavigationStack {
            Form {
                TextField(String(localized: "provider.name"), text: $group.name)
                Picker(String(localized: "group.strategy"), selection: $group.strategy) {
                    Text(String(localized: "group.fallback")).tag("fallback")
                    Text(String(localized: "group.balance")).tag("loadBalance")
                }
                if group.strategy == "fallback" { Toggle(String(localized: "group.any_error"), isOn: $group.fallbackOnAnyError) }
                Section(String(localized: "group.members")) {
                    ForEach(group.members, id: \.self) { member in
                        HStack {
                            Text(FamiliarProviderCatalog.descriptor(for: member.providerID)?.displayName ?? member.providerID)
                            Spacer()
                            Text(member.modelID).foregroundStyle(.secondary)
                        }
                    }
                    .onMove { group.members.move(fromOffsets: $0, toOffset: $1) }
                    .onDelete { group.members.remove(atOffsets: $0) }
                    Menu {
                        ForEach(FamiliarProviderCatalog.instances) { provider in
                            Menu(provider.displayName) {
                                ForEach(provider.curatedModels) { model in
                                    let reference = FamiliarModelReference(providerID: provider.id, modelID: model.id)
                                    Button(model.displayName) { group.members.append(reference) }.disabled(group.members.contains(reference))
                                }
                            }
                        }
                    } label: { Label(String(localized: "common.add"), systemImage: "plus") }
                }
                Section {
                    Button(String(localized: "provider.use")) { save(use: true) }
                } footer: { Text(String(localized: "group.footer")) }
            }
            .navigationTitle(String(localized: "group.title"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(String(localized: "common.cancel")) { dismiss() } }
                ToolbarItem(placement: .primaryAction) { EditButton() }
                ToolbarItem(placement: .confirmationAction) { Button(String(localized: "common.save")) { save(use: false) } }
            }
            .alert(String(localized: "settings.error.title"), isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button(String(localized: "common.ok"), role: .cancel) {}
            } message: { Text(errorMessage ?? "") }
        }
    }
    private func save(use: Bool) {
        do {
            try FamiliarModelGroupStore.save(group)
            if use { onSelect(group) }
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}
