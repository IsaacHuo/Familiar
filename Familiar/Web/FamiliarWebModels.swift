import Foundation

nonisolated enum FamiliarWebError: LocalizedError, FamiliarStructuredToolError, Sendable {
    case invalidQuery
    case invalidURL
    case httpsRequired
    case privateNetworkBlocked
    case dnsFailed
    case redirectBlocked
    case redirectLoop
    case tooManyRedirects
    case timeout
    case responseTooLarge
    case unsupportedContentType
    case unsupportedContentEncoding
    case malformedResponse
    case httpError(Int)
    case rateLimited
    case missingSearchAPIKey(String)
    case searchKeyRejected(String)
    case searchQuotaExceeded(String)
    case searchKeyLocked
    case searchUnavailable
    case searchChallenge
    case searchNoProgress
    case noReadableContent

    var code: String {
        switch self {
        case .invalidQuery: "invalid_query"
        case .invalidURL: "invalid_url"
        case .httpsRequired: "https_required"
        case .privateNetworkBlocked: "private_network_blocked"
        case .dnsFailed: "dns_failed"
        case .redirectBlocked: "redirect_blocked"
        case .redirectLoop: "redirect_loop"
        case .tooManyRedirects: "too_many_redirects"
        case .timeout: "timeout"
        case .responseTooLarge: "response_too_large"
        case .unsupportedContentType: "unsupported_content_type"
        case .unsupportedContentEncoding: "unsupported_content_encoding"
        case .malformedResponse: "parse_failed"
        case .httpError: "http_error"
        case .rateLimited: "rate_limited"
        case .missingSearchAPIKey: "missing_search_api_key"
        case .searchKeyRejected: "search_api_key_rejected"
        case .searchQuotaExceeded: "search_quota_exceeded"
        case .searchKeyLocked: "search_api_key_locked"
        case .searchUnavailable: "search_unavailable"
        case .searchChallenge: "search_challenge"
        case .searchNoProgress: "search_no_progress"
        case .noReadableContent: "no_readable_content"
        }
    }

    var isRetryable: Bool {
        switch self {
        case .dnsFailed, .timeout, .rateLimited, .searchUnavailable:
            true
        case .httpError(let status):
            status == 429 || (500...599).contains(status)
        default:
            false
        }
    }

    var errorDescription: String? {
        switch self {
        case .invalidQuery: "搜索词无效。"
        case .invalidURL: "网址无效。"
        case .httpsRequired: "只允许访问 HTTPS 网址。"
        case .privateNetworkBlocked: "不能访问本地或私有网络地址。"
        case .dnsFailed: "无法解析网站地址。"
        case .redirectBlocked: "网站重定向到了不允许的地址。"
        case .redirectLoop: "网站重定向形成了循环。"
        case .tooManyRedirects: "网站重定向次数过多。"
        case .timeout: "网络请求超时。"
        case .responseTooLarge: "网页内容超过读取上限。"
        case .unsupportedContentType: "网页内容类型不受支持。"
        case .unsupportedContentEncoding: "网页使用了不受支持的压缩方式。"
        case .malformedResponse: "网站返回了无法解析的响应。"
        case .httpError(let status): "网站返回 HTTP \(status)。"
        case .rateLimited: "搜索服务暂时限制了请求。"
        case .missingSearchAPIKey(let provider):
            String(format: String(localized: "error.web.search_api_key_missing", defaultValue: "Add a %@ API key in Web Search settings first."), provider)
        case .searchKeyRejected(let provider): "\(provider) 拒绝了当前 API Key，请在联网搜索设置中检查或更换。"
        case .searchQuotaExceeded(let provider): "\(provider) 账户额度已用完或套餐受限。"
        case .searchKeyLocked: "设备尚未解锁，暂时无法读取搜索 API Key。"
        case .searchUnavailable: "搜索服务当前不可用。"
        case .searchChallenge: "搜索服务要求人机验证，当前无法读取结果。"
        case .searchNoProgress: "连续搜索没有新增来源。请读取已有来源并根据已有证据回答，不要继续重复搜索。"
        case .noReadableContent: "网页没有可读取的正文。"
        }
    }
}

nonisolated struct FamiliarWebSearchResult: Codable, Equatable, Sendable {
    let sourceID: String
    let position: Int
    let title: String
    let url: String
    let displayURL: String
    let snippet: String?
}

nonisolated struct FamiliarWebSearchOutput: Codable, Sendable {
    let query: String
    let engine: String
    let contentTrust: String
    let results: [FamiliarWebSearchResult]
    let truncated: Bool
    /// Display name of the keyed provider that failed before the keyless fallback answered.
    var fallbackFrom: String? = nil
}

nonisolated struct FamiliarWebFetchOutput: Codable, Sendable {
    let sourceID: String
    let finalURL: String
    let title: String?
    let mimeType: String
    let contentTrust: String
    let text: String
    let truncated: Bool
    let accessedAt: Date
    let contentHash: String

    var capture: FamiliarWebCapture {
        .init(captureID: sourceID, urlString: finalURL, accessedAt: accessedAt,
              contentHash: contentHash, text: text, truncated: truncated, sourceID: sourceID)
    }
}

nonisolated struct FamiliarWebCapture: Codable, Sendable, Equatable {
    let captureID: String
    let urlString: String
    let accessedAt: Date
    let contentHash: String
    let text: String
    let truncated: Bool
    let sourceID: String

    /// Keep provenance beside the captured body, including in future Project input.
    /// The stored file hash covers this whole document; contentHash identifies the body.
    var fileOriginKey: String { "web:" + captureID + "|" + String(accessedAt.timeIntervalSince1970) + "|" + contentHash }

    var resourceText: String {
        """
        [Captured web page; untrusted external content]
        URL: \(urlString)
        Fetched at: \(ISO8601DateFormatter().string(from: accessedAt))
        Source ID: \(sourceID)
        Captured text SHA-256: \(contentHash)
        Truncated: \(truncated)

        \(text)
        """
    }
}

nonisolated enum FamiliarSourceIdentifier {
    /// Six digest bytes, i.e. the first twelve hex characters. Identical output to
    /// the previous inline implementation, so existing source IDs keep matching.
    static func make(for url: URL) -> String {
        "src_" + FamiliarHash.sha256(url.absoluteString).prefix(12)
    }
}
