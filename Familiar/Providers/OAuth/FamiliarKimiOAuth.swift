// Adapted from OpenMinis KimiOAuthManager / KimiDeviceFlow at 4ef2900 (GPL-3.0).
import Foundation

nonisolated enum FamiliarOAuthError: LocalizedError, Sendable {
    case remote(String)
    case missingCredential
    case expired
    var errorDescription: String? {
        switch self {
        case .remote(let message): FamiliarProviderHTTP.sanitizedMessage(message)
        case .missingCredential: String(localized: "oauth.missing")
        case .expired: String(localized: "oauth.expired")
        }
    }
}

nonisolated struct FamiliarOAuthToken: Codable, Sendable {
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Date?
    var accountID: String? = nil
}

actor FamiliarKimiOAuth {
    static let shared = FamiliarKimiOAuth()
    private let clientID = "17e5f671-d194-4dfb-9706-5516cb48c098"
    private var refreshes: [String: Task<FamiliarOAuthToken, Error>] = [:]

    func begin() async throws -> FamiliarKimiDeviceFlow.DeviceAuthorization {
        let (data, status) = try await post(path: FamiliarKimiDeviceFlow.deviceAuthorizationPath, parameters: ["client_id": clientID])
        guard (200..<300).contains(status), let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw FamiliarOAuthError.remote(FamiliarProviderHTTP.errorMessage(from: data)) }
        return try FamiliarKimiDeviceFlow.parseDeviceAuthorization(json)
    }

    func finish(_ authorization: FamiliarKimiDeviceFlow.DeviceAuthorization, instanceID: String) async throws {
        var interval = max(authorization.interval, 1)
        let deadline = Date().addingTimeInterval(authorization.expiresIn)
        while Date() < deadline {
            try await Task.sleep(for: .seconds(interval))
            let (data, status) = try await post(path: FamiliarKimiDeviceFlow.tokenPath, parameters: ["client_id": clientID, "grant_type": "urn:ietf:params:oauth:grant-type:device_code", "device_code": authorization.deviceCode])
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw FamiliarOAuthError.expired }
            switch FamiliarKimiDeviceFlow.classifyPoll(json: json, httpOK: (200..<300).contains(status)) {
            case .success(let access, let refresh, let seconds):
                let token = FamiliarOAuthToken(accessToken: access, refreshToken: refresh, expiresAt: seconds.map { Date().addingTimeInterval($0) })
                try save(token, instanceID: instanceID)
                return
            case .pending: continue
            case .slowDown: interval = FamiliarKimiDeviceFlow.bumpedInterval(interval)
            case .denied(let message), .expired(let message), .fatal(let message): throw FamiliarOAuthError.remote(message)
            }
        }
        throw FamiliarOAuthError.expired
    }

    func accessToken(instanceID: String) async throws -> String {
        guard let token = FamiliarOAuthCredentialStore.load(instanceID: instanceID) else { throw FamiliarOAuthError.missingCredential }
        guard let expires = token.expiresAt, expires < Date().addingTimeInterval(300) else { return token.accessToken }
        if let task = refreshes[instanceID] { return try await task.value.accessToken }
        let task = Task { try await self.refresh(token, instanceID: instanceID) }
        refreshes[instanceID] = task
        defer { refreshes[instanceID] = nil }
        return try await task.value.accessToken
    }

    private func refresh(_ token: FamiliarOAuthToken, instanceID: String) async throws -> FamiliarOAuthToken {
        guard let refresh = token.refreshToken else { throw FamiliarOAuthError.expired }
        let (data, status) = try await post(path: FamiliarKimiDeviceFlow.tokenPath, parameters: ["client_id": clientID, "grant_type": "refresh_token", "refresh_token": refresh])
        guard (200..<300).contains(status), let json = try JSONSerialization.jsonObject(with: data) as? [String: Any], let access = json["access_token"] as? String else {
            // A transport/server failure must not silently erase the last credential.
            throw FamiliarOAuthError.remote(FamiliarProviderHTTP.errorMessage(from: data))
        }
        let result = FamiliarOAuthToken(accessToken: access, refreshToken: json["refresh_token"] as? String ?? refresh, expiresAt: (json["expires_in"] as? Double).map { Date().addingTimeInterval($0) })
        // Another login may have replaced the credential while the HTTP call ran.
        guard FamiliarOAuthCredentialStore.load(instanceID: instanceID)?.refreshToken == token.refreshToken else {
            guard let current = FamiliarOAuthCredentialStore.load(instanceID: instanceID) else { throw FamiliarOAuthError.missingCredential }
            return current
        }
        try save(result, instanceID: instanceID)
        return result
    }

    private func save(_ token: FamiliarOAuthToken, instanceID: String) throws {
        try FamiliarOAuthCredentialStore.save(token, instanceID: instanceID)
    }
    private func post(path: String, parameters: [String: String]) async throws -> (Data, Int) {
        var request = URLRequest(url: URL(string: FamiliarKimiDeviceFlow.authHost + path)!)
        request.httpMethod = "POST"; request.timeoutInterval = 30
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var components = URLComponents()
        components.queryItems = parameters.map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = Data((components.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B").utf8)
        let (data, response) = try await FamiliarProviderHTTP.session.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? -1)
    }
}

nonisolated struct FamiliarKimiModelProvider: FamiliarModelProvider, Sendable {
    let descriptor: FamiliarProviderDescriptor
    var providerID: String { descriptor.id }
    func stream(request: FamiliarModelRequest) -> AsyncThrowingStream<FamiliarModelStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let token = try await FamiliarKimiOAuth.shared.accessToken(instanceID: descriptor.id)
                    let provider = FamiliarOpenAICompatibleModelProvider(descriptor: descriptor, apiKey: token)
                    for try await event in provider.stream(request: request) { continuation.yield(event) }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }
}

nonisolated enum FamiliarOAuthCredentialStore {
    static func load(instanceID: String) -> FamiliarOAuthToken? {
        guard let value = FamiliarKeychainStore.load(for: "oauth." + instanceID) else { return nil }
        return try? JSONDecoder().decode(FamiliarOAuthToken.self, from: Data(value.utf8))
    }
    static func save(_ token: FamiliarOAuthToken, instanceID: String) throws {
        try FamiliarKeychainStore.save(String(decoding: JSONEncoder().encode(token), as: UTF8.self), for: "oauth." + instanceID)
    }
}

nonisolated struct FamiliarCodexModelProvider: FamiliarModelProvider, Sendable {
    let descriptor: FamiliarProviderDescriptor
    var providerID: String { descriptor.id }
    func stream(request: FamiliarModelRequest) -> AsyncThrowingStream<FamiliarModelStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let token = try await FamiliarBrowserOAuth.shared.codexAccessToken(instanceID: descriptor.id)
                    var headers = descriptor.additionalHeaders
                    headers["Version"] = "0.144.1"
                    headers["Openai-Beta"] = "responses=experimental"
                    headers["User-Agent"] = "codex_cli_rs/0.144.1 (iOS; arm64)"
                    headers["Originator"] = "codex_cli_rs"
                    if let accountID = token.accountID { headers["Chatgpt-Account-Id"] = accountID }
                    let resolved = FamiliarProviderDescriptor(id: descriptor.id, displayName: descriptor.displayName, protocolKind: .openAIResponses, baseURL: descriptor.baseURL, chatPath: descriptor.chatPath, modelsPath: nil, authStyle: .bearer, additionalHeaders: headers, curatedModels: descriptor.curatedModels, openAIChat: nil, isCustom: false)
                    let provider = FamiliarStructuredModelProvider(descriptor: resolved, apiKey: token.accessToken)
                    for try await event in provider.stream(request: request) { continuation.yield(event) }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }
}
