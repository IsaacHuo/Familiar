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

        let payload = try JSONDecoder().decode(OpenAIModelsResponse.self, from: data)
        let availableIDs = Set(payload.data.lazy.map(\.id).filter { !$0.isEmpty })
        let models = descriptor.curatedModels.filter { availableIDs.contains($0.id) }
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
