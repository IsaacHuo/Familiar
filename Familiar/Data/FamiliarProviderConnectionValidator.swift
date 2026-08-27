import Foundation

nonisolated enum FamiliarProviderConnectionError: LocalizedError, Sendable {
    case invalidResponse
    case modelUnavailable(String)
    case rejected(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            String(localized: "provider.validation.invalid_response")
        case .modelUnavailable(let modelID):
            String(format: String(localized: "provider.validation.model_unavailable"), modelID)
        case .rejected(let statusCode, let message):
            String(format: String(localized: "provider.validation.rejected"), statusCode, message)
        }
    }
}

nonisolated enum FamiliarProviderConnectionValidator {
    static func validate(
        descriptor: FamiliarProviderDescriptor,
        modelID: String,
        apiKey: String
    ) async throws {
        if descriptor.modelsPath != nil {
            let models = try await FamiliarModelCatalogService.models(for: descriptor, apiKey: apiKey)
            guard models.contains(where: { $0.id == modelID }) else {
                throw FamiliarProviderConnectionError.modelUnavailable(modelID)
            }
            return
        }

        let provider = FamiliarProviderFactory.makeProvider(for: descriptor, apiKey: apiKey)
        let request = FamiliarModelRequest(
            model: modelID,
            messages: [
                .system("Reply with OK."),
                .user("Connection test")
            ],
            tools: []
        )
        var receivedContent = false
        for try await event in provider.stream(request: request) {
            switch event {
            case .textDelta(let text):
                if !text.isEmpty { receivedContent = true }
            case .reasoningSummaryDelta:
                break
            case .toolCallDelta:
                break
            case .completed:
                break
            }
            if receivedContent { break }
        }
        guard receivedContent else { throw FamiliarProviderConnectionError.invalidResponse }
    }
}
