import Observation
import SwiftData
import SwiftUI
import UIKit

struct FamiliarRecordCollectionSurface: View {
    let surface: FamiliarSurfaceDescriptor
    @State private var selectedFilter: String?
    @State private var showsAllRecords = false

    init(surface: FamiliarSurfaceDescriptor) {
        self.surface = surface
        _selectedFilter = State(initialValue: nil)
    }

    var body: some View {
        if case .recordCollection(let collection) = surface.resultEnvelope?.presentation.content {
            let filter = FamiliarRecordPresentation.filter(for: collection)
            let records = FamiliarRecordPresentation.filtered(collection.records, by: filter, value: selectedFilter)
            VStack(alignment: .leading, spacing: FamiliarAISurfaceMetric.spaceM) {
                HStack(alignment: .firstTextBaseline, spacing: FamiliarAISurfaceMetric.spaceS) {
                    Label(surface.title, systemImage: "list.bullet.rectangle")
                        .font(FamiliarTypography.secondary.weight(.semibold))
                        .foregroundStyle(FamiliarTheme.ink)
                    Spacer(minLength: 0)
                    Text(collection.records.count, format: .number)
                        .font(FamiliarTypography.caption.monospacedDigit())
                        .foregroundStyle(FamiliarTheme.inkTertiary)
                }

                if let filter {
                    FamiliarRecordFilterChips(filter: filter, selected: $selectedFilter)
                }

                if records.isEmpty {
                    Text(String(localized: "records.empty", defaultValue: "No records"))
                        .font(FamiliarTypography.caption)
                        .foregroundStyle(FamiliarTheme.inkSecondary)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(records.prefix(3).enumerated()), id: \.element.id) { index, record in
                            FamiliarRecordRow(record: record)
                            if index < min(records.count, 3) - 1 {
                                Rectangle()
                                    .fill(FamiliarTheme.line)
                                    .frame(height: FamiliarAISurfaceMetric.hairline)
                            }
                        }
                    }
                }

                if collection.records.count > 3 {
                    Button {
                        showsAllRecords = true
                    } label: {
                        Label(String(localized: "records.view_all", defaultValue: "Search all records"), systemImage: "magnifyingglass")
                            .font(FamiliarTypography.caption.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(FamiliarTheme.accentInk)
                    .accessibilityIdentifier("surface.records.details")
                }
                if let attribution = FamiliarWeatherAttribution(surface: surface) {
                    FamiliarWeatherAttributionView(attribution: attribution)
                }
            }
            .padding(.vertical, FamiliarAISurfaceMetric.spaceS)
            .fullScreenCover(isPresented: $showsAllRecords) {
                FamiliarRecordCollectionDetailView(collection: collection, initialFilter: selectedFilter,
                    weatherAttribution: FamiliarWeatherAttribution(surface: surface))
            }
        }
    }
}

struct FamiliarRecordFilter: Equatable {
    let fieldName: String
    let values: [String]
}

enum FamiliarRecordPresentation {
    static func filter(for collection: FamiliarToolPresentationPayload.RecordCollection) -> FamiliarRecordFilter? {
        let preferredNames = ["status", "completed", "type", "mimeType"]
        for name in preferredNames {
            let values = collection.records.compactMap { record in
                record.fields.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
            }
            let unique = Array(Set(values)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            if unique.count > 1 { return .init(fieldName: name, values: unique) }
        }
        return nil
    }

    static func filtered(
        _ records: [FamiliarToolPresentationPayload.Record],
        by filter: FamiliarRecordFilter?,
        value: String?
    ) -> [FamiliarToolPresentationPayload.Record] {
        guard let filter, let value else { return records }
        return records.filter { record in
            record.fields.contains { $0.name.caseInsensitiveCompare(filter.fieldName) == .orderedSame && $0.value == value }
        }
    }

    static func matches(_ record: FamiliarToolPresentationPayload.Record, query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        return record.id.localizedCaseInsensitiveContains(query) || record.fields.contains {
            $0.name.localizedCaseInsensitiveContains(query) || $0.value.localizedCaseInsensitiveContains(query)
        }
    }

    static func displayValue(_ value: String, fieldName: String) -> String {
        if fieldName.caseInsensitiveCompare("completed") == .orderedSame {
            if value.caseInsensitiveCompare("true") == .orderedSame { return String(localized: "task.status.completed", defaultValue: "Completed") }
            if value.caseInsensitiveCompare("false") == .orderedSame { return String(localized: "task.status.pending", defaultValue: "Pending") }
        }
        return value
    }
}

struct FamiliarRecordFilterChips: View {
    let filter: FamiliarRecordFilter
    @Binding var selected: String?

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: FamiliarAISurfaceMetric.spaceXS) {
                chip(title: String(localized: "records.filter.all", defaultValue: "All"), value: nil)
                ForEach(filter.values, id: \.self) { value in
                    chip(title: FamiliarRecordPresentation.displayValue(value, fieldName: filter.fieldName), value: value)
                }
            }
        }
        .scrollIndicators(.hidden)
        .accessibilityLabel(String(localized: "records.filter", defaultValue: "Record filter"))
    }

    private func chip(title: String, value: String?) -> some View {
        Button {
            selected = value
        } label: {
            Text(title)
                .font(FamiliarTypography.caption.weight(.medium))
                .foregroundStyle(selected == value ? FamiliarTheme.accentInk : FamiliarTheme.inkSecondary)
                .padding(.horizontal, FamiliarAISurfaceMetric.spaceM)
                .frame(minHeight: 30)
                .background(selected == value ? FamiliarTheme.accentTint : FamiliarTheme.inset, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct FamiliarRecordRow: View {
    let record: FamiliarToolPresentationPayload.Record

    private var primary: FamiliarToolPresentationPayload.RecordField? {
        let preferred = ["title", "name", "filename"]
        for name in preferred {
            if let field = record.fields.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) { return field }
        }
        return record.fields.first
    }

    private var secondary: [FamiliarToolPresentationPayload.RecordField] {
        let preferred = ["status", "completed", "start", "due", "end", "type", "mimeType", "calendar", "list"]
        return preferred.compactMap { name in
            record.fields.first { field in
                field.name.caseInsensitiveCompare(name) == .orderedSame && field.name != primary?.name
            }
        }.prefix(3).map { $0 }
    }

    var body: some View {
        HStack(alignment: .top, spacing: FamiliarAISurfaceMetric.spaceM) {
            Image(systemName: statusSymbol)
                .font(FamiliarTypography.caption.weight(.semibold))
                .foregroundStyle(FamiliarTheme.accent)
                .frame(width: FamiliarAISurfaceMetric.icon, height: FamiliarAISurfaceMetric.icon)
            VStack(alignment: .leading, spacing: FamiliarAISurfaceMetric.spaceXS) {
                Text(primary?.value ?? String(localized: "runtime.ui.record", defaultValue: "Record"))
                    .font(FamiliarTypography.secondary.weight(.medium))
                    .foregroundStyle(FamiliarTheme.ink)
                    .lineLimit(2)
                ForEach(secondary, id: \.name) { field in
                    Text("\(fieldTitle(field.name)): \(formatted(field))")
                        .font(FamiliarTypography.caption)
                        .foregroundStyle(FamiliarTheme.inkSecondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, FamiliarAISurfaceMetric.spaceS)
        .accessibilityElement(children: .combine)
    }

    private var statusSymbol: String {
        guard let completed = record.fields.first(where: { $0.name.caseInsensitiveCompare("completed") == .orderedSame })?.value else {
            return "doc.text"
        }
        return completed.caseInsensitiveCompare("true") == .orderedSame ? "checkmark.circle.fill" : "circle"
    }

    private func formatted(_ field: FamiliarToolPresentationPayload.RecordField) -> String {
        let dateFields = ["start", "end", "due"]
        if dateFields.contains(where: { field.name.caseInsensitiveCompare($0) == .orderedSame }),
           let date = try? FamiliarISO8601.date(field.value) {
            return date.formatted(date: .abbreviated, time: .shortened)
        }
        return FamiliarRecordPresentation.displayValue(field.value, fieldName: field.name)
    }

    private func fieldTitle(_ name: String) -> String {
        switch name.lowercased() {
        case "status": String(localized: "records.field.status", defaultValue: "Status")
        case "completed": String(localized: "records.field.status", defaultValue: "Status")
        case "start": String(localized: "records.field.start", defaultValue: "Starts")
        case "end": String(localized: "records.field.end", defaultValue: "Ends")
        case "due": String(localized: "records.field.due", defaultValue: "Due")
        case "type", "mimetype": String(localized: "records.field.type", defaultValue: "Type")
        case "calendar": String(localized: "records.field.calendar", defaultValue: "Calendar")
        case "list": String(localized: "records.field.list", defaultValue: "List")
        default: name
        }
    }
}

struct FamiliarRecordCollectionDetailView: View {
    let collection: FamiliarToolPresentationPayload.RecordCollection
    let weatherAttribution: FamiliarWeatherAttribution?
    @State private var selectedFilter: String?
    @State private var searchText = ""
    @Environment(\.dismiss) private var dismiss

    init(collection: FamiliarToolPresentationPayload.RecordCollection, initialFilter: String?,
         weatherAttribution: FamiliarWeatherAttribution? = nil) {
        self.collection = collection
        self.weatherAttribution = weatherAttribution
        _selectedFilter = State(initialValue: initialFilter)
    }

    var body: some View {
        let filter = FamiliarRecordPresentation.filter(for: collection)
        let filtered = FamiliarRecordPresentation.filtered(collection.records, by: filter, value: selectedFilter)
            .filter { FamiliarRecordPresentation.matches($0, query: searchText) }
        NavigationStack {
            List {
                if let weatherAttribution {
                    FamiliarWeatherAttributionView(attribution: weatherAttribution)
                }
                if let filter {
                    Section {
                        FamiliarRecordFilterChips(filter: filter, selected: $selectedFilter)
                    }
                }
                ForEach(filtered, id: \.id) { record in
                    FamiliarRecordRow(record: record)
                }
            }
            .listStyle(.plain)
            .searchable(text: $searchText, prompt: String(localized: "records.search", defaultValue: "Search records"))
            .navigationTitle(collection.summary)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    FamiliarDismissButton()
                }
            }
        }
    }
}

/// The one file card. Delivered File records, prepared exports and unavailable
/// files all render through the same tile, preview and share affordances.
