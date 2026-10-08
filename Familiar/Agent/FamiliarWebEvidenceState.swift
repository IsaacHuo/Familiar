import Foundation

/// One Run's observations, including failed reads. Never grants authorization.
/// Retained tasks coalesce in-flight work and keep the original capture time.
actor FamiliarWebEvidenceState {
    typealias Search = (FamiliarWebSearchOutput, [FamiliarSource])
    typealias Page = (FamiliarWebFetchOutput, FamiliarSource)
    private var searches: [String: Task<Search, Error>] = [:]
    private var pages: [String: Task<Page, Error>] = [:]
    private var knownURLs: Set<String> = []
    private var searchesWithoutProgress = 0

    static func normalizedQuery(_ query: String) -> String {
        query.precomposedStringWithCompatibilityMapping
            .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ").lowercased()
    }

    func search(query: String, providerID: String, language: String,
                operation: @escaping @Sendable () async throws -> Search) async throws -> Search {
        try Task.checkCancellation()
        let key = providerID + "|" + language + "|" + Self.normalizedQuery(query)
        if let task = searches[key] { return try await value(of: task) }
        guard searchesWithoutProgress < 2 else { throw FamiliarWebError.searchNoProgress }
        let task = Task { try await operation() }
        searches[key] = task
        do {
            let result = try await value(of: task)
            let urls = Set(result.0.results.compactMap { try? FamiliarWebURLPolicy.normalize($0.url).absoluteString })
            let added = urls.subtracting(knownURLs)
            knownURLs.formUnion(urls)
            searchesWithoutProgress = added.isEmpty ? searchesWithoutProgress + 1 : 0
            return result
        } catch is CancellationError {
            searches[key] = nil
            throw CancellationError()
        } catch {
            searchesWithoutProgress += 1
            throw error
        }
    }

    func fetch(url: String, operation: @escaping @Sendable (String) async throws -> Page) async throws -> Page {
        try Task.checkCancellation()
        let key = try FamiliarWebURLPolicy.normalize(url).absoluteString
        if let task = pages[key] { return try await value(of: task) }
        let task = Task { try await operation(key) }
        pages[key] = task
        do {
            let result = try await value(of: task)
            let final = try FamiliarWebURLPolicy.normalize(result.0.finalURL).absoluteString
            // Unknown aliases cannot be predicted before their redirects are observed.
            if pages[final] == nil { pages[final] = task }
            return result
        } catch is CancellationError {
            pages[key] = nil
            throw CancellationError()
        }
    }

    private func value<T: Sendable>(of task: Task<T, Error>) async throws -> T {
        let result = try await withTaskCancellationHandler {
            try await task.value
        } onCancel: { task.cancel() }
        try Task.checkCancellation()
        return result
    }
}
