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

    @Binding var isAutomaticMemoryEnabled: Bool
    @State private var editing: FamiliarMemoryItem?
    @State private var editedContent = ""
    @State private var asksToClearAll = false
    @State private var errorMessage: String?

    private var visibleItems: [FamiliarMemoryItem] {
        items.filter(\.isVisible)
    }

    var body: some View {
        List {
            Section {
                Toggle(
                    String(localized: "settings.memory.enabled", defaultValue: "Remember across conversations"),
                    isOn: $isAutomaticMemoryEnabled
                )
            } footer: {
                Text(String(localized: "settings.memory.enabled.footer", defaultValue: "When off, Familiar neither proposes new memories nor reads existing ones. Stored memories stay on this device and remain listed below."))
            }

            if visibleItems.isEmpty {
                Section {
                    ContentUnavailableView(
                        String(localized: "settings.memory.empty", defaultValue: "Nothing remembered yet"),
                        systemImage: "brain",
                        description: Text(String(localized: "settings.memory.empty.detail", defaultValue: "Familiar only remembers what you confirm."))
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
                    Button(String(localized: "settings.memory.clear_all", defaultValue: "Delete All Memories"), role: .destructive) {
                        asksToClearAll = true
                    }
                }
            }
        }
        .navigationTitle(String(localized: "settings.memory.title", defaultValue: "Memory"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { item in
            editor(for: item)
        }
        .alert(
            String(localized: "settings.memory.clear_all.confirm", defaultValue: "Delete all memories?"),
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
            HStack(spacing: FamiliarSpacing.xSmall) {
                Text(scopeLabel(item.scope))
                Text("·")
                // Provenance is shown so a remembered item can always be traced back to
                // where it came from.
                Text(item.provenance)
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
    }

    private func scopeLabel(_ scope: FamiliarMemoryScope) -> String {
        switch scope {
        case .global: String(localized: "settings.memory.scope.global", defaultValue: "All conversations")
        case .project: String(localized: "settings.memory.scope.project", defaultValue: "This project only")
        case .conversation: String(localized: "settings.memory.scope.conversation", defaultValue: "This conversation only")
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
            errorMessage = FamiliarMemoryError.invalidContent.localizedDescription
            return
        }
        // The same rule as the tool and persistence boundaries: an edited memory must not
        // become a way to store a secret by hand.
        guard !FamiliarMemoryPolicy.looksSensitive(trimmed) else {
            errorMessage = FamiliarMemoryError.sensitiveContent.localizedDescription
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
            errorMessage = error.localizedDescription
        }
    }

    private func delete(_ item: FamiliarMemoryItem) {
        modelContext.delete(item)
        do { try modelContext.save() } catch { errorMessage = error.localizedDescription }
    }

    private func clearAll() {
        visibleItems.forEach(modelContext.delete)
        do { try modelContext.save() } catch { errorMessage = error.localizedDescription }
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
