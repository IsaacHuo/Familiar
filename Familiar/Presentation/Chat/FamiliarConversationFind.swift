import Observation
import SwiftData
import SwiftUI

@MainActor @Observable final class FamiliarConversationFindState {
    var isPresented = false
    var query = ""
    let results = FamiliarLocalSearchModel()
    private(set) var selectedMessageID: UUID?
    private(set) var navigationID = UUID()
    var index: Int? { results.result.messages.firstIndex { $0.id == selectedMessageID } }
    var term: String { isPresented ? query.trimmingCharacters(in: .whitespacesAndNewlines) : "" }

    func selectFirst() {
        selectedMessageID = results.result.messages.first?.id
        navigationID = UUID()
    }

    func move(_ step: Int, container: ModelContainer) async {
        guard isPresented, !term.isEmpty, !results.loading, results.request?.query == term else { return }
        let originalQuery = term, originalSelection = selectedMessageID
        let next = (index ?? -1) + step
        guard next >= 0 else { return }
        if next >= results.result.messages.count, results.hasMore { await results.loadMore(container: container) }
        guard !Task.isCancelled, isPresented, term == originalQuery, results.request?.query == originalQuery, selectedMessageID == originalSelection,
              results.result.messages.indices.contains(next) else { return }
        selectedMessageID = results.result.messages[next].id
        navigationID = UUID()
    }
}

struct FamiliarConversationFindBar: View {
    @Environment(\.modelContext) private var context
    let conversationID: UUID
    @Bindable var state: FamiliarConversationFindState
    @FocusState private var focused: Bool
    @State private var step = 0
    @State private var retry = false
    private var request: FamiliarLocalSearchRequest {
        .init(query: state.term, conversationIDs: [conversationID], includeTitles: false)
    }

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(String(localized: "local_search.find"), text: $state.query)
                    .focused($focused).submitLabel(.search).accessibilityIdentifier("chat.find.input")
                Button { state.isPresented = false } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
                    .buttonStyle(.plain).accessibilityLabel(String(localized: "common.done"))
                    .accessibilityIdentifier("chat.find.close")
            }.padding(.leading, 14).familiarGlassSurface()
            if !state.term.isEmpty {
                HStack(spacing: 8) {
                    if state.results.loading { ProgressView().controlSize(.small) }
                    else if let error = state.results.error {
                        Text(error).lineLimit(1)
                        Button(String(localized: "local_search.retry")) { retry = true }
                    } else {
                        Text(state.results.result.messageCount == 0 ? String(localized: "local_search.no_matches") :
                            String(format: String(localized: "local_search.count"), (state.index ?? -1) + 1, state.results.result.messageCount))
                            .monospacedDigit().accessibilityIdentifier("chat.find.count")
                    }
                    Spacer(minLength: 4)
                    Button { step = 1 } label: { Image(systemName: "chevron.up").frame(width: 44, height: 44) }
                        .disabled(state.results.loading || (state.index ?? -1) + 1 >= state.results.result.messageCount)
                        .accessibilityLabel(String(localized: "local_search.previous")).accessibilityIdentifier("chat.find.previous")
                    Button { step = -1 } label: { Image(systemName: "chevron.down").frame(width: 44, height: 44) }
                        .disabled(state.results.loading || (state.index ?? 0) == 0)
                        .accessibilityLabel(String(localized: "local_search.next")).accessibilityIdentifier("chat.find.next")
                }.font(.caption).padding(.leading, 14).familiarGlassSurface()
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 4)
        .task { focused = true }
        .task(id: request) {
            await state.results.update(request, container: context.container)
            guard !Task.isCancelled else { return }
            state.selectFirst()
        }
        .task(id: step) {
            guard step != 0 else { return }
            await state.move(step, container: context.container)
            step = 0
        }
        .task(id: retry) {
            guard retry else { return }
            await state.results.update(request, container: context.container)
            if !Task.isCancelled { state.selectFirst() }
            retry = false
        }
    }
}

extension EnvironmentValues {
    @Entry var familiarMessageSearchTerm = ""
}
