import Observation
import SwiftUI

/// Scroll geometry is observed by the floating chrome, never by the list snapshot owner.
@MainActor @Observable
final class FamiliarChatListChromeState {
    var pageProgress: CGFloat = 0
    @ObservationIgnored var offsets: [FamiliarChatListFilter: CGFloat] = [:]
}

struct FamiliarChatProjectPager: View {
    @Environment(\.familiarReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .subheadline) private var tabsHeight: CGFloat = 48
    let rowsByFilter: [FamiliarChatListFilter: [FamiliarConversationListSnapshot]]
    let projects: [FamiliarProject]
    @Binding var filter: FamiliarChatListFilter
    let editing: Bool
    @Binding var selection: Set<UUID>
    let counts: [UUID: Int]
    let specialRowsByFilter: [FamiliarChatListFilter: AnyView]
    let specialRowsRevision: Int
    let onManage: () -> Void
    let onOpen: (UUID) -> Void
    let onAction: (UUID, FamiliarConversationListAction) -> Void
    let preview: (UUID) -> [FamiliarMessageSnapshot]
    @State private var chrome = FamiliarChatListChromeState()
    @State private var pageID: FamiliarChatListFilter? = .recent
    private var filters: [FamiliarChatListFilter] { [.recent] + projects.map { .project($0.id) } }

    var body: some View {
        GeometryReader { safeViewport in
            let safeFrame = safeViewport.frame(in: .global)
            let fullHeader = tabsHeight + 12
            ZStack(alignment: .top) {
                GeometryReader { contentViewport in
                    let contentFrame = contentViewport.frame(in: .global)
                    let topOverlap = max(0, safeFrame.minY - contentFrame.minY)
                    let bottomOverlap = max(0, contentFrame.maxY - safeFrame.maxY)
                    pages(size: contentViewport.size, topInset: topOverlap + fullHeader, bottomInset: bottomOverlap + 8)
                }
                // Only the list extends beneath native navigation and the tab bar.
                .ignoresSafeArea(.container, edges: .vertical)

                FamiliarChatListFloatingHeader(chrome: chrome, filters: filters, projects: projects,
                    filter: $filter, pageID: $pageID,
                    counts: counts,
                    tabsHeight: tabsHeight, onManage: onManage)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: safeViewport.size.width, height: safeViewport.size.height, alignment: .top)
        }

    }

    private func pages(size: CGSize, topInset: CGFloat, bottomInset: CGFloat) -> some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(filters, id: \.self) { item in
                    let visible = rowsByFilter[item] ?? []
                    let specialRows = specialRowsByFilter[item]
                    FamiliarConversationList(rows: visible, isEditing: editing, selection: $selection,
                        initialOffset: chrome.offsets[item] ?? 0, reduceMotion: reduceMotion,
                        onScroll: { offset in
                            chrome.offsets[item] = offset
                        }, onOpen: onOpen, onAction: onAction, preview: preview,
                        topInset: topInset, bottomInset: bottomInset,
                        specialRows: specialRows, specialRowsRevision: specialRowsRevision)
                        .overlay {
                            if visible.isEmpty && specialRows == nil {
                                ContentUnavailableView(String(localized: "chat.list.empty"), systemImage: "bubble.left.and.bubble.right")
                                    .padding(.top, topInset).padding(.bottom, bottomInset)
                                    .allowsHitTesting(false)
                            }
                        }
                        .frame(width: size.width, height: size.height).id(item)
                        .accessibilityHidden(item != filter)
                }
            }.scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging).scrollIndicators(.hidden).scrollDisabled(editing)
        .scrollPosition(id: $pageID)
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.x / max($0.containerSize.width, 1) } action: { _, value in chrome.pageProgress = value }
        .onChange(of: pageID) { _, value in if let value { filter = value } }
        .onChange(of: filter) { _, value in
            if pageID != value { pageID = value }
        }
    }

}

private struct FamiliarChatListFloatingHeader: View {
    @Environment(\.familiarReduceMotion) private var reduceMotion
    let chrome: FamiliarChatListChromeState
    let filters: [FamiliarChatListFilter]
    let projects: [FamiliarProject]
    @Binding var filter: FamiliarChatListFilter
    @Binding var pageID: FamiliarChatListFilter?
    private var progress: CGFloat { chrome.pageProgress }
    let counts: [UUID: Int]
    let tabsHeight: CGFloat
    let onManage: () -> Void
    @State private var stripWidth: CGFloat = 0
    @State private var stripOffset: CGFloat = 0
    @State private var tabFrames: [FamiliarChatListFilter: CGRect] = [:]
    var body: some View {
        GlassEffectContainer(spacing: 8) {
            tabs.padding(.bottom, 8).padding(.top, 4)
                .padding(.horizontal, 16)
        }
    }

    private var tabs: some View {
        ScrollViewReader { proxy in
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(filters, id: \.self) { item in
                    Button {
                        filter = item
                        withAnimation(reduceMotion ? nil : FamiliarTelegramMotion.panel) { pageID = item }
                    } label: {
                        HStack(spacing: 5) {
                            Text(title(item)).font(.subheadline.weight(.semibold)).lineLimit(1)
                            if case .project(let id) = item, let count = counts[id], count > 0 {
                                Text(count, format: .number).font(.caption2.weight(.bold))
                            }
                        }.padding(.horizontal, 16).frame(height: tabsHeight - 4)
                    }
                    .buttonStyle(.plain).accessibilityAddTraits(filter == item ? .isSelected : [])
                    .accessibilityLabel(title(item))
                    .accessibilityValue(unreadDescription(item))
                    .id(item)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("project-tabs")) } action: { tabFrames[item] = $0 }
                }
                Button(action: onManage) { Image(systemName: "folder.badge.gearshape").frame(width: 44, height: tabsHeight - 4) }
                    .buttonStyle(.plain).accessibilityLabel(String(localized: "project.manage"))
                    .accessibilityIdentifier("chats.manageProjects")
            }
            .coordinateSpace(name: "project-tabs")
            .background(alignment: .topLeading) {
                if let frame = selectionFrame {
                    Capsule().fill(.primary.opacity(0.08))
                        .frame(width: frame.width, height: frame.height)
                        .offset(x: frame.minX, y: frame.minY).allowsHitTesting(false)
                }
            }
            .padding(2)
        }
        .frame(height: tabsHeight)
        .familiarGlassSurface(interactive: true, cornerRadius: tabsHeight * 0.5)
        .accessibilityIdentifier("chats.projectTabs")
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { stripWidth = $0 }
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.x } action: { _, value in stripOffset = value }
        .onChange(of: filter) { _, value in
            guard let frame = tabFrames[value], stripWidth > 0 else { return }
            let lookahead: CGFloat = 100
            let available = max(1, stripWidth - frame.width)
            let anchor: CGFloat
            if stripOffset + stripWidth - lookahead < frame.maxX { anchor = max(0, 1 - lookahead / available) }
            else if stripOffset > frame.minX - lookahead { anchor = min(1, lookahead / available) }
            else { return }
            withAnimation(reduceMotion ? nil : FamiliarTelegramMotion.panel) { proxy.scrollTo(value, anchor: .init(x: anchor, y: 0.5)) }
        }
        .onChange(of: filters) { _, values in
            tabFrames = tabFrames.filter { values.contains($0.key) }
            proxy.scrollTo(filter, anchor: .center)
        }
        }
    }

    private var selectionFrame: CGRect? {
        guard !filters.isEmpty else { return nil }
        let position = min(max(progress, 0), CGFloat(filters.count - 1))
        let lower = Int(floor(position)), upper = min(lower + 1, filters.count - 1)
        guard let start = tabFrames[filters[lower]] else { return nil }
        let end = tabFrames[filters[upper]] ?? start, fraction = position - CGFloat(lower)
        return CGRect(x: start.minX + (end.minX - start.minX) * fraction, y: start.minY,
            width: start.width + (end.width - start.width) * fraction, height: start.height)
    }
    private func title(_ item: FamiliarChatListFilter) -> String {
        switch item { case .recent: String(localized: "chat.recent"); case .project(let id): projects.first { $0.id == id }?.displayName ?? "" }
    }
    private func unreadDescription(_ item: FamiliarChatListFilter) -> String {
        guard case .project(let id) = item, let count = counts[id], count > 0 else { return "" }
        return String(format: String(localized: "accessibility.unread_conversations"), count)
    }
}
