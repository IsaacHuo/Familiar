import CryptoKit
import Foundation

nonisolated enum FamiliarWebError: LocalizedError, Sendable {
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
    case searchUnavailable
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
        case .searchUnavailable: "search_unavailable"
        case .noReadableContent: "no_readable_content"
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
        case .searchUnavailable: "搜索服务当前不可用。"
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
}

nonisolated struct FamiliarWebFetchOutput: Codable, Sendable {
    let sourceID: String
    let finalURL: String
    let title: String?
    let mimeType: String
    let contentTrust: String
    let text: String
    let truncated: Bool
}

nonisolated enum FamiliarSourceIdentifier {
    static func make(for url: URL) -> String {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        return "src_" + digest.prefix(6).map { String(format: "%02x", $0) }.joined()
    }
}
