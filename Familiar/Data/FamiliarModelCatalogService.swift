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

        let (data, response) = try await FamiliarProviderHTTP.session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw FamiliarProviderRequestError.invalidResponse(provider: descriptor.displayName)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw FamiliarProviderRequestError.server(
                provider: descriptor.displayName,
                statusCode: http.statusCode,
                message: FamiliarProviderHTTP.errorMessage(from: data)
            )
        }

        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let rows = (object?["data"] ?? object?["models"]) as? [[String: Any]] ?? []
        let identifiers = Set(rows.compactMap { row -> String? in
            if descriptor.protocolKind == .gemini {
                guard (row["supportedGenerationMethods"] as? [String])?.contains("generateContent") == true else { return nil }
                return (row["name"] as? String)?.replacingOccurrences(of: "models/", with: "")
            }
            return row["id"] as? String
        }.filter { !$0.isEmpty })
        let models = identifiers.sorted().map { id in
            descriptor.curatedModels.first(where: { $0.id == id })
                ?? FamiliarModelDescriptor(id: id)
        }
        guard !models.isEmpty else {
            throw FamiliarProviderRequestError.invalidResponse(provider: descriptor.displayName)
        }
        return models
    }

    private struct OpenAIModelsResponse: Decodable {
        let data: [Model]
        struct Model: Decodable { let id: String }
    }

}
