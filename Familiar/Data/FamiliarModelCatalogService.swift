import Foundation

nonisolated enum FamiliarModelCatalogService {
    static func models(
        for descriptor: FamiliarProviderDescriptor,
        apiKey: String
    ) async throws -> [FamiliarModelDescriptor] {
        guard let modelsPath = descriptor.modelsPath else {
            return descriptor.curatedModels
        }

        let url = try FamiliarProviderHTTP.authorizedURL(
            descriptor: descriptor,
            path: modelsPath,
            apiKey: apiKey
        )
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        FamiliarProviderHTTP.applyHeaders(to: &request, descriptor: descriptor, apiKey: apiKey)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw FamiliarProviderRequestError.invalidResponse(provider: descriptor.displayName)
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? String(localized: "error.provider.unknown_server")
            throw FamiliarProviderRequestError.server(
                provider: descriptor.displayName,
                statusCode: http.statusCode,
                message: String(message.prefix(500))
            )
        }

        let identifiers: [(String, String?)]
        switch descriptor.protocolKind {
        case .geminiGenerateContent:
            let payload = try JSONDecoder().decode(GeminiModelsResponse.self, from: data)
            identifiers = payload.models
                .filter { $0.supportedGenerationMethods?.contains("generateContent") != false }
                .map { ($0.name.replacingOccurrences(of: "models/", with: ""), $0.displayName) }
        case .anthropicMessages:
            let payload = try JSONDecoder().decode(AnthropicModelsResponse.self, from: data)
            identifiers = payload.data.map { ($0.id, $0.displayName) }
        case .openAIChat:
            let payload = try JSONDecoder().decode(OpenAIModelsResponse.self, from: data)
            identifiers = payload.data.map { ($0.id, nil) }
        }

        let models: [FamiliarModelDescriptor] = identifiers
            .filter { !$0.0.isEmpty }
            .map { (id: String, name: String?) -> FamiliarModelDescriptor in
                let curated = descriptor.curatedModels.first(where: { $0.id == id })
                return FamiliarModelDescriptor(
                    id: id,
                    displayName: name ?? curated?.displayName ?? id,
                    capabilities: curated?.capabilities ?? .textOnly
                )
            }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        return models.isEmpty ? descriptor.curatedModels : models
    }

    private struct OpenAIModelsResponse: Decodable {
        let data: [Model]
        struct Model: Decodable { let id: String }
    }

    private struct AnthropicModelsResponse: Decodable {
        let data: [Model]
        struct Model: Decodable {
            let id: String
            let displayName: String?
            enum CodingKeys: String, CodingKey {
                case id
                case displayName = "display_name"
            }
        }
    }

    private struct GeminiModelsResponse: Decodable {
        let models: [Model]
        struct Model: Decodable {
            let name: String
            let displayName: String?
            let supportedGenerationMethods: [String]?
        }
    }
}
