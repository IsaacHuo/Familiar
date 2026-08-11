import Foundation

nonisolated enum FamiliarProviderConnectionError: LocalizedError, Sendable {
    case invalidResponse
    case rejected(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            String(localized: "provider.validation.invalid_response")
        case .rejected(let statusCode, let message):
            String(
                format: String(localized: "provider.validation.rejected"),
                statusCode,
                message
            )
        }
    }
}

nonisolated enum FamiliarProviderConnectionValidator {
    static func validate(provider: FamiliarProvider, apiKey: String) async throws {
        var request = URLRequest(url: provider.modelsEndpoint)
        request.timeoutInterval = 20
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw FamiliarProviderConnectionError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw FamiliarProviderConnectionError.rejected(
                statusCode: http.statusCode,
                message: String((body?.isEmpty == false ? body! : "Unknown error").prefix(320))
            )
        }
    }
}
