import AVFoundation
import Contacts
import CoreBluetooth
import CoreLocation
import EventKit
import HealthKit
import MusicKit
import Photos
import Speech
import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers


struct FamiliarMemorySettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FamiliarMemoryItem.updatedAt, order: .reverse) private var items: [FamiliarMemoryItem]
    @Query private var projects: [FamiliarProject]
    @Query private var conversations: [FamiliarConversation]
    var scope: FamiliarWorkScope? = nil
    var showsGlobalControl = true
    @State private var filter = FamiliarMemoryListFilter.all

    @Binding var isAutomaticMemoryEnabled: Bool
    @State private var editing: FamiliarMemoryItem?
    @State private var editedContent = ""
    @State private var asksToClearAll = false
    @State private var errorMessage: String?
    @State private var editorError: String?

    private var visibleItems: [FamiliarMemoryItem] {
        items.filter { item in
            guard item.isVisible else { return false }
            if let scope {
                switch scope {
                case .project(let id): return item.scope == .project && item.projectID == id
                case .conversation(let id): return item.scope == .conversation && item.conversationID == id
                }
            }
            return filter == .all || item.scope.rawValue == filter.rawValue
        }
    }

    var body: some View {
        List {
            if showsGlobalControl {
            Section {
                Toggle(
                    String(localized: "settings.memory.enabled", defaultValue: "Automatic Memory"),
                    isOn: $isAutomaticMemoryEnabled
                )
            } footer: {
                Text(String(localized: "settings.memory.enabled.footer", defaultValue: "Eligible preferences and facts can be saved automatically with receipts and Undo. Turning this off stops automatic writes and context use; saved memory stays on this device in its original scope."))
            }

            } else {
                Section { Text(String(localized: "settings.memory.scoped_footer")).font(.subheadline).foregroundStyle(.secondary) }
            }
            if scope == nil {
                Picker(String(localized: "settings.memory.scope_filter"), selection: $filter) {
                    ForEach(FamiliarMemoryListFilter.allCases) { Text($0.title).tag($0) }
                }
            }
            if visibleItems.isEmpty {
                Section {
                    ContentUnavailableView(
                        String(localized: "settings.memory.empty", defaultValue: "Nothing remembered yet"),
                        systemImage: "brain",
                        description: Text(String(localized: "settings.memory.empty.detail", defaultValue: "Eligible preferences and facts can be remembered automatically, with sources and Undo records."))
                    )
                }
            } else {
                Section {
                    ForEach(visibleItems) { item in
                        Button {
                            editedContent = item.content
                            editing = item
                        } label: {
                            HStack(spacing: FamiliarSpacing.small) {
                                memoryRow(item)
                                Image(systemName: "chevron.right")
                                    .font(FamiliarTypography.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                                    .accessibilityHidden(true)
                            }
                            .frame(minHeight: FamiliarControlSize.minimumHitTarget)
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button(String(localized: "common.delete"), role: .destructive) {
                                delete(item)
                            }
                        }
                    }
                } header: {
                    Text(String(format: String(localized: "settings.memory.count", defaultValue: "%@ remembered"), NSNumber(value: visibleItems.count)))
                } footer: {
                    Text(String(localized: "settings.memory.footer", defaultValue: "Each memory records where it came from. Memory is never treated as an instruction and cannot grant permissions."))
                }

                Section {
                    Button(String(localized: scope == nil && filter == .all ? "settings.memory.clear_all" : "settings.memory.clear_scope"), role: .destructive) {
                        asksToClearAll = true
                    }
                }
            }
        }
        .navigationTitle(scopeTitle)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { item in
            editor(for: item)
        }
        .alert(
            String(localized: scope == nil && filter == .all ? "settings.memory.clear_all.confirm" : "settings.memory.clear_scope.confirm"),
            isPresented: $asksToClearAll
        ) {
            Button(String(localized: "common.cancel"), role: .cancel) {}
            Button(String(localized: "common.delete"), role: .destructive) { clearAll() }
        } message: {
            Text(String(localized: "settings.memory.clear_all.detail", defaultValue: "This cannot be undone. Conversations and project files are not affected."))
        }
        .alert(String(localized: "settings.error.title"), isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button(String(localized: "common.ok"), role: .cancel) {}
        } message: {
            Text(errorMessage ?? String(localized: "error.unknown"))
        }
    }

    private func memoryRow(_ item: FamiliarMemoryItem) -> some View {
        VStack(alignment: .leading, spacing: FamiliarSpacing.xSmall) {
            Text(item.content)
                .font(FamiliarTypography.body)
                .multilineTextAlignment(.leading)
            Text(ownerLabel(item)).font(.caption).foregroundStyle(.secondary)
            Text(item.provenance).font(.caption2).foregroundStyle(.tertiary).lineLimit(2)
        }
    }

    private var scopeTitle: String {
        let title = String(localized: "settings.memory.title")
        guard let scope else { return title }
        switch scope {
        case .project(let id): return (projects.first { $0.id == id }?.displayName ?? String(localized: "project.unavailable")) + " · " + title
        case .conversation(let id): return (conversations.first { $0.id == id }?.title ?? String(localized: "settings.memory.conversation_missing")) + " · " + title
        }
    }

    private func ownerLabel(_ item: FamiliarMemoryItem) -> String {
        switch item.scope {
        case .global: return String(localized: "settings.memory.scope.global")
        case .project:
            let name = projects.first { $0.id == item.projectID }?.displayName ?? String(localized: "project.unavailable")
            return String(format: String(localized: "settings.memory.project_owner"), name)
        case .conversation:
            let name = conversations.first { $0.id == item.conversationID }?.title ?? String(localized: "settings.memory.conversation_missing")
            let owner = String(format: String(localized: "settings.memory.conversation_owner"), name)
            if let projectID = item.projectID, let project = projects.first(where: { $0.id == projectID }) { return project.displayName + " · " + owner }
            return owner
        }
    }

    private func editor(for item: FamiliarMemoryItem) -> some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $editedContent)
                        .frame(minHeight: 140)
                        .accessibilityLabel(String(localized: "settings.memory.editor", defaultValue: "Memory text"))
                } footer: {
                    Text(String(format: String(localized: "settings.memory.editor.footer", defaultValue: "Up to %@ characters. Secrets, passwords and keys are refused."), NSNumber(value: FamiliarMemoryPolicy.maximumContentLength)))
                }
            }
            .navigationTitle(String(localized: "settings.memory.edit", defaultValue: "Edit Memory"))
            .navigationBarTitleDisplayMode(.inline)
            .alert(String(localized: "settings.error.title"), isPresented: Binding(get: { editorError != nil }, set: { if !$0 { editorError = nil } })) {
                Button(String(localized: "common.ok"), role: .cancel) {}
            } message: { Text(editorError ?? "") }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.cancel")) { editing = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "common.save")) { save(item) }
                        .fontWeight(.semibold)
                        .disabled(editedContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func save(_ item: FamiliarMemoryItem) {
        let trimmed = editedContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= FamiliarMemoryPolicy.maximumContentLength else {
            editorError = FamiliarMemoryError.invalidContent.localizedDescription
            return
        }
        // The same rule as the tool and persistence boundaries: an edited memory must not
        // become a way to store a secret by hand.
        guard !FamiliarMemoryPolicy.looksSensitive(trimmed) else {
            editorError = FamiliarMemoryError.sensitiveContent.localizedDescription
            return
        }
        item.content = trimmed
        // The dedup key is derived from the content, so editing must rewrite it or the
        // next identical write would not be recognised as the same memory.
        item.normalizedKey = FamiliarMemoryService.normalizedKey(
            content: trimmed,
            scope: item.scope,
            projectID: item.projectID,
            conversationID: item.conversationID
        )
        item.provenance = String(localized: "settings.memory.provenance.edited", defaultValue: "edited in Settings")
        item.updatedAt = Date()
        do {
            try modelContext.save()
            editing = nil
        } catch {
            modelContext.rollback()
            editorError = error.localizedDescription
        }
    }

    private func delete(_ item: FamiliarMemoryItem) {
        modelContext.delete(item)
        do { try modelContext.save() } catch { modelContext.rollback(); errorMessage = error.localizedDescription }
    }

    private func clearAll() {
        visibleItems.forEach(modelContext.delete)
        do { try modelContext.save() } catch { modelContext.rollback(); errorMessage = error.localizedDescription }
    }
}

struct FamiliarSoulSettingsView: View {
    @Binding var systemPrompt: String

    var body: some View {
        Form {
            Section {
                TextEditor(text: $systemPrompt)
                    .frame(minHeight: 260)
                    .accessibilityLabel(String(localized: "settings.soul.editor", defaultValue: "Personality prompt"))
            } header: {
                Text(String(localized: "settings.soul.personality", defaultValue: "Personality"))
            } footer: {
                Text(String(localized: "settings.soul.footer", defaultValue: "This changes Familiar's tone and response style. Tool permissions and safety rules remain enforced by the app."))
            }

            Section {
                HStack {
                    Text(String(localized: "settings.soul.characters", defaultValue: "Characters"))
                    Spacer()
                    Text("\(min(systemPrompt.count, 3_000)) / 3,000")
                        .foregroundStyle(.secondary)
                }
                Button(String(localized: "settings.soul.restore", defaultValue: "Restore Familiar Default"), role: .destructive) {
                    systemPrompt = FamiliarSettings.defaultValue.systemPrompt
                }
            }
        }
        .onChange(of: systemPrompt) { _, value in
            if value.count > 3_000 { systemPrompt = String(value.prefix(3_000)) }
        }
        .navigationTitle(String(localized: "settings.hub.soul", defaultValue: "Response Preferences"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Steppers rather than free text: the budgets are clamped by
