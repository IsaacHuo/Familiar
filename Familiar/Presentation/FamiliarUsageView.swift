import SwiftUI
import SwiftData

struct FamiliarUsageView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var runs: [FamiliarAgentRun]
    let conversationID: UUID?
    var body: some View {
        NavigationStack {
            List {
                let selected = runs.filter { $0.conversation?.id == conversationID && conversationID != nil }
                usageRow("usage.input", values: selected.map(\.inputTokenCount))
                usageRow("usage.output", values: selected.map(\.outputTokenCount))
                usageRow("usage.cached", values: selected.map(\.cachedInputTokenCount))
                ForEach(selected.sorted { $0.startedAt > $1.startedAt }) { run in
                    if let data = run.modelRequestsJSON?.data(using: .utf8), let requests = try? JSONDecoder().decode([FamiliarModelReference].self, from: data) {
                        Section(run.startedAt.formatted()) {
                            ForEach(Array(requests.enumerated()), id: \.offset) { _, request in
                                LabeledContent(FamiliarProviderCatalog.descriptor(for: request.providerID)?.displayName ?? request.providerID, value: request.modelID)
                            }
                        }
                    }
                }
                Section { Text(String(localized: "usage.footer")).font(.footnote).foregroundStyle(.secondary) }
            }
            .navigationTitle(String(localized: "usage.title"))
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(String(localized: "common.done")) { dismiss() } } }
        }
    }
    private func usageRow(_ key: String.LocalizationValue, values: [Int?]) -> some View {
        let reported = values.compactMap { $0 }
        return LabeledContent(String(localized: key), value: reported.isEmpty ? String(localized: "usage.unreported") : reported.reduce(0, +).formatted())
    }
}
