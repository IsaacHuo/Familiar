// Adapted from OpenMinis CodexOAuthManager / OpenRouterOAuthManager, 4ef2900 (GPL-3.0).
import Foundation
import UIKit
import SafariServices
import CryptoKit

@MainActor final class FamiliarBrowserOAuth: NSObject, SFSafariViewControllerDelegate {
    static let shared = FamiliarBrowserOAuth()
    private var server: FamiliarOAuthCallbackServer?
    private weak var browser: SFSafariViewController?
    private var signingIn = false
    private var refreshes: [String: Task<FamiliarOAuthToken, Error>] = [:]

    func login(kind: String, instanceID: String) async throws {
        guard !signingIn else { throw FamiliarOAuthError.remote(String(localized: "oauth.busy")) }
        signingIn = true
        let port: UInt16 = kind == "codex" ? 1455 : 3000
        let path = kind == "codex" ? "/auth/callback" : "/callback"
        let callback = "http://localhost:\(port)\(path)"
        let listener = FamiliarOAuthCallbackServer(port: port, path: path)
        server = listener
        defer { listener.stop(); server = nil; browser?.dismiss(animated: true); browser = nil; signingIn = false }
        var random = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, random.count, &random) == errSecSuccess else { throw FamiliarOAuthError.expired }
        let verifier = Self.base64URL(Data(random))
        let challenge = Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        let state = UUID().uuidString
        try await listener.start()
        var url = URLComponents(string: kind == "codex" ? "https://auth.openai.com/oauth/authorize" : "https://openrouter.ai/auth")!
        if kind == "codex" {
            url.queryItems = [
                .init(name: "response_type", value: "code"), .init(name: "client_id", value: "app_EMoamEEZ73f0CkXaXp7hrann"),
                .init(name: "redirect_uri", value: callback), .init(name: "scope", value: "openid profile email offline_access"),
                .init(name: "code_challenge", value: challenge), .init(name: "code_challenge_method", value: "S256"),
                .init(name: "state", value: state), .init(name: "id_token_add_organizations", value: "true"),
                .init(name: "codex_cli_simplified_flow", value: "true"), .init(name: "originator", value: "codex_cli_rs")
            ]
        } else {
            url.queryItems = [.init(name: "callback_url", value: callback), .init(name: "code_challenge", value: challenge), .init(name: "code_challenge_method", value: "S256")]
        }
        try present(url.url!)
        let result = try await listener.wait()
        if kind == "codex" {
            guard result.state == state else { throw FamiliarOAuthError.expired }
            let token = try await codexToken(["grant_type": "authorization_code", "client_id": "app_EMoamEEZ73f0CkXaXp7hrann", "code": result.code, "redirect_uri": callback, "code_verifier": verifier])
            try FamiliarOAuthCredentialStore.save(token, instanceID: instanceID)
        } else {
            var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/auth/keys")!)
            request.httpMethod = "POST"; request.timeoutInterval = 30
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["code": result.code, "code_verifier": verifier, "code_challenge_method": "S256"])
            let (data, response) = try await FamiliarProviderHTTP.session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any], let key = json["key"] as? String else { throw FamiliarOAuthError.remote(FamiliarProviderHTTP.errorMessage(from: data)) }
            try FamiliarKeychainStore.save(key, for: instanceID)
        }
    }
    func safariViewControllerDidFinish(_ controller: SFSafariViewController) { server?.stop() }
    func cancel() { server?.stop() }

    func codexAccessToken(instanceID: String) async throws -> FamiliarOAuthToken {
        guard let current = FamiliarOAuthCredentialStore.load(instanceID: instanceID) else { throw FamiliarOAuthError.missingCredential }
        if current.expiresAt.map({ $0 > Date().addingTimeInterval(300) }) != false { return current }
        if let task = refreshes[instanceID] { return try await task.value }
        guard let refreshToken = current.refreshToken else { throw FamiliarOAuthError.expired }
        let task = Task { @MainActor in
            let refreshed = try await self.codexToken(["grant_type": "refresh_token", "client_id": "app_EMoamEEZ73f0CkXaXp7hrann", "refresh_token": refreshToken])
            guard FamiliarOAuthCredentialStore.load(instanceID: instanceID)?.refreshToken == current.refreshToken else {
                guard let replacement = FamiliarOAuthCredentialStore.load(instanceID: instanceID) else { throw FamiliarOAuthError.missingCredential }
                return replacement
            }
            let token = FamiliarOAuthToken(accessToken: refreshed.accessToken, refreshToken: refreshed.refreshToken ?? refreshToken, expiresAt: refreshed.expiresAt, accountID: refreshed.accountID ?? current.accountID)
            try FamiliarOAuthCredentialStore.save(token, instanceID: instanceID)
            return token
        }
        refreshes[instanceID] = task
        defer { refreshes[instanceID] = nil }
        return try await task.value
    }
    private func codexToken(_ body: [String: String]) async throws -> FamiliarOAuthToken {
        var request = URLRequest(url: URL(string: "https://auth.openai.com/oauth/token")!)
        request.httpMethod = "POST"; request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await FamiliarProviderHTTP.session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any], let token = json["access_token"] as? String else { throw FamiliarOAuthError.remote(FamiliarProviderHTTP.errorMessage(from: data)) }
        var accountID: String?
        if let idToken = json["id_token"] as? String {
            let pieces = idToken.split(separator: ".")
            if pieces.count >= 2 {
                var encoded = String(pieces[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
                encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)
                if let data = Data(base64Encoded: encoded), let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    accountID = (payload["https://api.openai.com/auth"] as? [String: Any])?["chatgpt_account_id"] as? String
                }
            }
        }
        return .init(accessToken: token, refreshToken: json["refresh_token"] as? String, expiresAt: (json["expires_in"] as? Double).map { Date().addingTimeInterval($0) }, accountID: accountID)
    }
    private func present(_ url: URL) throws {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState == .foregroundActive }),
              let root = scene.windows.first(where: \.isKeyWindow)?.rootViewController else { throw FamiliarOAuthError.expired }
        var presenter = root
        while let next = presenter.presentedViewController { presenter = next }
        let controller = SFSafariViewController(url: url)
        controller.delegate = self; browser = controller
        presenter.present(controller, animated: true)
    }
    private static func base64URL(_ data: Data) -> String { data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
}
