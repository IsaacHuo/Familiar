import AppIntents
import SwiftUI
import WidgetKit

@main
struct FamiliarWidgetsBundle: WidgetBundle {
    var body: some Widget {
        FamiliarLauncherWidget()
        FamiliarOpenControl()
    }
}

private struct FamiliarLauncherEntry: TimelineEntry {
    let date: Date
}

private struct FamiliarLauncherProvider: TimelineProvider {
    func placeholder(in context: Context) -> FamiliarLauncherEntry {
        FamiliarLauncherEntry(date: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (FamiliarLauncherEntry) -> Void) {
        completion(FamiliarLauncherEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FamiliarLauncherEntry>) -> Void) {
        completion(Timeline(entries: [FamiliarLauncherEntry(date: .now)], policy: .never))
    }
}

private struct FamiliarLauncherWidgetView: View {
    @Environment(\.widgetFamily) private var family

    private let newConversationURL = URL(string: "familiar://new")!

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.title2)
                    .accessibilityLabel(Text("widget.launch.accessibility_label"))
            case .accessoryRectangular:
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                    VStack(alignment: .leading, spacing: 1) {
                        Text("widget.launch.title")
                            .font(.headline)
                        Text("widget.launch.subtitle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            default:
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.tint)

                    Spacer(minLength: 0)

                    Text("widget.launch.title")
                        .font(.headline)
                        .lineLimit(2)
                    Text("widget.launch.subtitle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .padding(2)
            }
        }
        .widgetURL(newConversationURL)
        .containerBackground(for: .widget) {
            Color(uiColor: .secondarySystemBackground)
        }
    }
}

private struct FamiliarLauncherWidget: Widget {
    static let kind = "com.isaachuo.familiar.launcher"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: FamiliarLauncherProvider()) { entry in
            FamiliarLauncherWidgetView()
        }
        .configurationDisplayName("widget.launch.display_name")
        .description("widget.launch.description")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

private struct FamiliarOpenControl: ControlWidget {
    static let kind = "com.isaachuo.familiar.open-control"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: OpenFamiliarControlIntent(target: .app)) {
                Label("control.open.title", systemImage: "bubble.left.and.bubble.right")
            }
        }
        .displayName("control.open.display_name")
        .description("control.open.description")
    }
}
