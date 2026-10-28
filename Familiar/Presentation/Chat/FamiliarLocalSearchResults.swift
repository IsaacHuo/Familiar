import Observation
import SwiftData
import SwiftUI

struct FamiliarSearchHighlightedText: View {
    let text: String
    let query: String
    private var value: AttributedString {
        guard !query.isEmpty, let range = text.range(of: query, options: FamiliarSearchText.options, locale: .current) else { return AttributedString(text) }
        var match = AttributedString(text[range])
        match.foregroundColor = FamiliarTheme.accent
        return AttributedString(text[..<range.lowerBound]) + match + AttributedString(text[range.upperBound...])
    }
    var body: some View { Text(value) }
}

struct FamiliarLocalSearchResults: View {
    @Environment(\.modelContext) private var context
    let request: FamiliarLocalSearchRequest
    @Binding var searchAll: Bool
    let onOpen: (UUID) -> Void
    let onMessage: (UUID, UUID) -> Void
    @State private var model = FamiliarLocalSearchModel()
    @State private var loadingMore = false

    var body: some View {
        List {
            Toggle(String(localized: "chat.search.all"), isOn: $searchAll)
            if request.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ContentUnavailableView(String(localized: "local_search.prompt"), systemImage: "magnifyingglass",
                    description: Text(String(localized: "local_search.local")))
                    .listRowSeparator(.hidden)
            } else {
                if model.loading && model.result.messages.isEmpty && model.result.conversations.isEmpty {
                    HStack { Spacer(); ProgressView(); Spacer() }.listRowSeparator(.hidden)
                }
                if let error = model.error {
                    Text(error).foregroundStyle(.secondary)
                    Button(String(localized: "local_search.retry")) { loadingMore = true }
                }
                if !model.result.conversations.isEmpty {
                    Section(String(localized: "tab.chats") + " · \(model.result.conversationCount)") {
                        ForEach(model.result.conversations) { hit in
                            Button { onOpen(hit.conversationID) } label: { row(hit, message: false) }.buttonStyle(.plain)
                        }
                    }
                }
                if !model.result.messages.isEmpty {
                    Section(String(localized: "chat.search.messages") + " · \(model.result.messageCount)") {
                        ForEach(model.result.messages) { hit in
                            Button { onMessage(hit.conversationID, hit.id) } label: { row(hit, message: true) }.buttonStyle(.plain)
                                .accessibilityIdentifier("search.message." + hit.id.uuidString)
                        }
                    }
                }
                if !model.loading && model.error == nil && model.result.messageCount == 0 && model.result.conversationCount == 0 {
                    ContentUnavailableView.search(text: request.query).listRowSeparator(.hidden)
                }
                if model.hasMore {
                    Button { loadingMore = true } label: {
                        if model.loading { ProgressView() } else { Text(String(localized: "local_search.more")) }
                    }.disabled(model.loading)
                }
            }
        }
        .listStyle(.plain).scrollDismissesKeyboard(.interactively)
        .task(id: request) { await model.update(request, container: context.container) }
        .task(id: loadingMore) {
            guard loadingMore else { return }
            if model.error != nil && model.result.messages.isEmpty && model.result.conversations.isEmpty {
                await model.update(request, container: context.container)
            } else { await model.loadMore(container: context.container) }
            loadingMore = false
        }
    }

    private func row(_ hit: FamiliarLocalSearchHit, message: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                FamiliarSearchHighlightedText(text: hit.title, query: request.query).font(.headline).lineLimit(1)
                Spacer(minLength: 8)
                if hit.isArchived { Label(String(localized: "chat.archived"), systemImage: "archivebox").font(.caption2).foregroundStyle(.secondary) }
            }
            if !hit.excerpt.isEmpty {
                FamiliarSearchHighlightedText(text: hit.excerpt, query: request.query)
                    .font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
            }
            if message { Text(hit.date, format: .dateTime.month().day().hour().minute()).font(.caption2).foregroundStyle(.tertiary) }
        }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
    }
}

@MainActor @Observable final class FamiliarHomeSearchState {
    var query = ""
    var all = false
}

/// Query keystrokes invalidate the header/results, not the home list snapshot owner.
struct FamiliarHomeSearchResults: View {
    @Bindable var state: FamiliarHomeSearchState
    let conversationIDs: [UUID]
    let onOpen: (UUID) -> Void
    let onMessage: (UUID, UUID) -> Void
    var body: some View {
        FamiliarLocalSearchResults(request: .init(query: state.query.trimmingCharacters(in: .whitespacesAndNewlines),
            conversationIDs: state.all ? nil : conversationIDs), searchAll: $state.all,
            onOpen: onOpen, onMessage: onMessage)
    }
}

/// Native drawer search replaces the independent Sheet. This modifier owns
/// query observation so keystrokes do not rebuild home list snapshots.
struct FamiliarHomeSearchPresentation: ViewModifier {
    @Bindable var state: FamiliarHomeSearchState
    @Binding var presented: Bool
    let conversationIDs: [UUID]
    let onOpen: (UUID) -> Void
    let onMessage: (UUID, UUID) -> Void

    func body(content: Content) -> some View {
        content
            .allowsHitTesting(!presented)
            .accessibilityHidden(presented)
            .overlay {
                if presented {
                    FamiliarHomeSearchResults(state: state, conversationIDs: conversationIDs,
                        onOpen: onOpen, onMessage: onMessage)
                        .background(FamiliarTheme.page)
                }
            }
            .searchable(text: $state.query, isPresented: $presented,
                placement: .navigationBarDrawer(displayMode: .automatic),
                prompt: String(localized: "drawer.search"))
    }
}
