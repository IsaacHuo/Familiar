import Foundation

/// One Run's observations, including failed reads. Never grants authorization.
/// Retained tasks coalesce in-flight work and keep the original capture time.
actor FamiliarWebEvidenceState {
    typealias Search = (FamiliarWebSearchOutput, [FamiliarSource])
    typealias Page = (FamiliarWebFetchOutput, FamiliarSource)
    private struct SearchKey: Hashable {
        let query: String
        let providerID: String
        let language: String
        let maximumResults: Int
        let recency: FamiliarSearchRecency?
    }
    private var searches: [SearchKey: Task<Search, Error>] = [:]
    private var pages: [String: Task<Page, Error>] = [:]
    private var capturedPages: [String: Page] = [:]
    private var pageAliases: [String: String] = [:]
    private var knownURLs: Set<String> = []
    private var searchesWithoutProgress = 0

    static func normalizedQuery(_ query: String) -> String {
        query.precomposedStringWithCompatibilityMapping
            .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ").lowercased()
    }

    func search(query: String, providerID: String, language: String,
                maximumResults: Int = 5, recency: FamiliarSearchRecency? = nil,
                operation: @escaping @Sendable () async throws -> Search) async throws -> Search {
        try Task.checkCancellation()
        let key = SearchKey(query: Self.normalizedQuery(query), providerID: providerID,
                            language: language, maximumResults: maximumResults, recency: recency)
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
        } catch {
            // A failure is not evidence: drop it so a later identical query can
            // retry, and do not count it as "no new sources". The real error is
            // reported to the model unchanged.
            searches[key] = nil
            throw error
        }
    }

    func fetch(url: String, operation: @escaping @Sendable (String) async throws -> Page) async throws -> Page {
        try Task.checkCancellation()
        let key = try FamiliarWebURLPolicy.normalize(url).absoluteString
        if let final = pageAliases[key], let captured = capturedPages[final] { return captured }
        if let task = pages[key] { return try await value(of: task) }
        let task = Task { try await capture(url: key, operation: operation) }
        pages[key] = task
        do {
            return try await value(of: task)
        } catch {
            // Failures are not evidence; a later attempt may succeed.
            pages[key] = nil
            throw error
        }
    }

    private func capture(url: String, operation: @escaping @Sendable (String) async throws -> Page) async throws -> Page {
        let result = try await operation(url)
        try Task.checkCancellation()
        let final = try FamiliarWebURLPolicy.normalize(result.0.finalURL).absoluteString
        // Concurrent, previously unknown aliases may both need a request, but
        // once their redirects are observed they share the first capture and ID.
        let captured = capturedPages[final] ?? result
        capturedPages[final] = captured
        pageAliases[url] = final
        pageAliases[final] = final
        return captured
    }

    private func value<T: Sendable>(of task: Task<T, Error>) async throws -> T {
        let result = try await withTaskCancellationHandler {
            try await task.value
        } onCancel: { task.cancel() }
        try Task.checkCancellation()
        return result
    }
}
