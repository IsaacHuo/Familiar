import Foundation
import SwiftUI

/// Derived from the native tool's durable result, never from model-written citations.
nonisolated struct FamiliarWeatherAttribution: Equatable, Sendable, Identifiable {
    let legalURL: URL
    var id: String { legalURL.absoluteString }

    private struct Payload: Decodable {
        let attributionServiceName: String
        let attributionLegalURL: String
    }

    init?(surface: FamiliarSurfaceDescriptor) {
        guard surface.phase == .succeeded,
              surface.toolName == "weather_forecast" || surface.toolName == "weather_history",
              let envelope = surface.resultEnvelope,
              let payload = try? JSONDecoder().decode(Payload.self, from: Data(envelope.modelContent.utf8)),
              !payload.attributionServiceName.isEmpty,
              let url = URL(string: payload.attributionLegalURL),
              url.scheme?.lowercased() == "https", url.host != nil else { return nil }
        legalURL = url
    }

    static func unique(in surfaces: [FamiliarSurfaceDescriptor]) -> [Self] {
        var seen: Set<String> = []
        return surfaces.compactMap(Self.init(surface:)).filter { seen.insert($0.id).inserted }
    }
}

struct FamiliarWeatherAttributionView: View {
    let attribution: FamiliarWeatherAttribution

    var body: some View {
        VStack(alignment: .leading, spacing: FamiliarSpacing.xSmall) {
            Text(verbatim: " Weather")
                .foregroundStyle(.primary)
                .accessibilityLabel("Apple Weather")
            Link(String(localized: "weather.attribution.legal"), destination: attribution.legalURL)
                .frame(minHeight: FamiliarControlSize.minimumHitTarget, alignment: .leading)
                .accessibilityIdentifier("weather.attribution.legal")
        }
        .font(FamiliarTypography.caption)
        .accessibilityIdentifier("weather.attribution")
    }
}
