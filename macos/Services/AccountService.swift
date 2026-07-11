import AppKit
import CryptoKit
import Foundation
import Network

enum AccountServiceError: LocalizedError {
    case invalidAuthFile
    case invalidTokenResponse
    case callback(String)
    case warmupIncomplete
    case http(Int)
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidAuthFile: return "当前 auth.json 中没有可用的 Codex 登录 token。"
        case .invalidTokenResponse: return "登录服务返回了无效 token。"
        case .callback(let message): return message
        case .warmupIncomplete: return "预热流在完成事件前结束。"
        case .http(let status): return "上游请求失败（HTTP \(status)）。"
        case .keychain: return "无法访问 macOS 钥匙串。"
        }
    }
}

struct AccountService: Sendable {
    let paths: AppPaths
    let keychain = KeychainStore()

    private let issuer = "https://auth.openai.com"
    private let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"
    private let usageURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
    private let warmupURL = URL(string: "https://chatgpt.com/backend-api/codex/responses")!

    init(paths: AppPaths = AppPaths()) { self.paths = paths }

    func load() throws -> [AccountRecord] {
        guard FileManager.default.fileExists(atPath: paths.accountPool.path) else { return [] }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([AccountRecord].self, from: Data(contentsOf: paths.accountPool))
    }

    func save(_ accounts: [AccountRecord]) throws {
        try FileManager.default.createDirectory(at: paths.codexHome, withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(accounts) + Data("\n".utf8)
        try data.write(to: paths.accountPool, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: paths.accountPool.path)
    }

    func importCurrent() throws -> (AccountRecord, AccountCredentials) {
        let object = try jsonObject(at: paths.auth)
        guard let tokens = object["tokens"] as? [String: Any],
              let access = tokens["access_token"] as? String, !access.isEmpty else { throw AccountServiceError.invalidAuthFile }
        let idToken = tokens["id_token"] as? String
        let accountID = (tokens["account_id"] as? String) ?? claim(idToken, key: "chatgpt_account_id")
        let id = accountID ?? UUID().uuidString
        let credentials = AccountCredentials(idToken: idToken, accessToken: access, refreshToken: tokens["refresh_token"] as? String, accountID: accountID, workspaceID: claim(idToken, key: "workspace_id"))
        return (record(for: id, credentials: credentials), credentials)
    }

    func login() async throws -> (AccountRecord, AccountCredentials) {
        let verifier = randomString(byteCount: 64)
        let state = randomString(byteCount: 32)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncodedString()
        let redirectURI = "http://localhost:1455/auth/callback"
        var components = URLComponents(string: "\(issuer)/oauth/authorize")!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"), URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI), URLQueryItem(name: "scope", value: "openid profile email offline_access api.connectors.read api.connectors.invoke"),
            URLQueryItem(name: "code_challenge", value: challenge), URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "id_token_add_organizations", value: "true"), URLQueryItem(name: "codex_cli_simplified_flow", value: "true"),
            URLQueryItem(name: "state", value: state), URLQueryItem(name: "originator", value: "codex_cli_rs")
        ]
        let callback = try await OAuthCallback.wait(for: state, redirectURI: redirectURI, authorizationURL: components.url!)
        let tokens = try await exchange(code: callback.code, verifier: verifier, redirectURI: redirectURI)
        let accountID = claim(tokens.idToken, key: "chatgpt_account_id") ?? claim(tokens.accessToken, key: "chatgpt_account_id") ?? UUID().uuidString
        let credentials = AccountCredentials(idToken: tokens.idToken, accessToken: tokens.accessToken, refreshToken: tokens.refreshToken, accountID: accountID, workspaceID: claim(tokens.idToken, key: "workspace_id"))
        return (record(for: accountID, credentials: credentials), credentials)
    }

    func refresh(_ account: AccountRecord) async throws -> AccountRecord {
        var credentials = try keychain.read(for: account.id)
        do {
            return try await withUsage(account, credentials: credentials)
        } catch AccountServiceError.http(401) where credentials.refreshToken != nil {
            credentials = try await refreshToken(credentials)
            try keychain.save(credentials, for: account.id)
            return try await withUsage(account, credentials: credentials)
        }
    }

    func warmup(_ account: AccountRecord) async throws -> AccountRecord {
        var credentials = try keychain.read(for: account.id)
        do {
            try await sendWarmup(credentials)
        } catch AccountServiceError.http(401) where credentials.refreshToken != nil {
            credentials = try await refreshToken(credentials); try keychain.save(credentials, for: account.id); try await sendWarmup(credentials)
        }
        return try await refresh(account)
    }

    func switchTo(_ account: AccountRecord) throws {
        let credentials = try keychain.read(for: account.id)
        let original = FileManager.default.fileExists(atPath: paths.auth.path) ? try Data(contentsOf: paths.auth) : nil
        let tokens: [String: Any] = [
            "id_token": credentials.idToken ?? NSNull(), "access_token": credentials.accessToken,
            "refresh_token": credentials.refreshToken ?? NSNull(), "account_id": credentials.accountID ?? account.id
        ]
        let object: [String: Any] = ["OPENAI_API_KEY": NSNull(), "tokens": tokens, "last_refresh": ISO8601DateFormatter().string(from: Date())]
        try FileManager.default.createDirectory(at: paths.accountBackupDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        if FileManager.default.fileExists(atPath: paths.auth.path) {
            let backup = paths.accountBackupDirectory.appendingPathComponent("auth-\(Int(Date().timeIntervalSince1970)).json")
            try FileManager.default.copyItem(at: paths.auth, to: backup)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backup.path)
        }
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) + Data("\n".utf8)
        try data.write(to: paths.auth, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: paths.auth.path)
        guard ((try? jsonObject(at: paths.auth)["tokens"] as? [String: Any])?["access_token"] as? String) == credentials.accessToken else {
            if let original { try? original.write(to: paths.auth, options: .atomic) }
            throw AccountServiceError.invalidAuthFile
        }
    }

    private func withUsage(_ account: AccountRecord, credentials: AccountCredentials) async throws -> AccountRecord {
        var request = URLRequest(url: usageURL); request.httpMethod = "GET"; request.timeoutInterval = 30
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        if let id = credentials.accountID ?? account.chatgptAccountID ?? credentials.workspaceID { request.setValue(id, forHTTPHeaderField: "ChatGPT-Account-ID") }
        request.setValue("https://chatgpt.com", forHTTPHeaderField: "Origin")
        request.setValue("https://chatgpt.com/", forHTTPHeaderField: "Referer")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let status = (response as? HTTPURLResponse)?.statusCode, 200..<300 ~= status else { throw AccountServiceError.http((response as? HTTPURLResponse)?.statusCode ?? 0) }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let rate = json["rate_limit"] as? [String: Any]
        let primary = window(rate?["primary_window"] as? [String: Any]); let secondary = window(rate?["secondary_window"] as? [String: Any])
        var updated = account; updated.usage = AccountUsageSnapshot(primaryRemainPercent: primary.remain, primaryResetsAt: primary.reset, secondaryRemainPercent: secondary.remain, secondaryResetsAt: secondary.reset, capturedAt: Date()); updated.lastRefresh = Date(); updated.lastError = nil; updated.status = "active"; return updated
    }

    private func sendWarmup(_ credentials: AccountCredentials) async throws {
        var request = URLRequest(url: warmupURL); request.httpMethod = "POST"; request.timeoutInterval = 90
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization"); request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://chatgpt.com", forHTTPHeaderField: "Origin"); request.setValue("https://chatgpt.com/", forHTTPHeaderField: "Referer")
        if let accountID = credentials.accountID ?? credentials.workspaceID { request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-ID") }
        request.httpBody = try JSONSerialization.data(withJSONObject: ["model": "gpt-5.3-codex", "instructions": "", "input": [["type": "message", "role": "user", "content": [["type": "input_text", "text": "hi"]]]], "stream": true, "store": false], options: [])
        let (data, response) = try await URLSession.shared.data(for: request); guard let status = (response as? HTTPURLResponse)?.statusCode, 200..<300 ~= status else { throw AccountServiceError.http((response as? HTTPURLResponse)?.statusCode ?? 0) }
        guard String(decoding: data, as: UTF8.self).contains("response.completed") else { throw AccountServiceError.warmupIncomplete }
    }

    private func exchange(code: String, verifier: String, redirectURI: String) async throws -> OAuthTokens {
        try await postForm(url: URL(string: "\(issuer)/oauth/token")!, fields: ["grant_type": "authorization_code", "code": code, "redirect_uri": redirectURI, "client_id": clientID, "code_verifier": verifier])
    }

    private func refreshToken(_ credentials: AccountCredentials) async throws -> AccountCredentials {
        guard let refresh = credentials.refreshToken else { throw AccountServiceError.invalidTokenResponse }
        let tokens = try await postForm(url: URL(string: "\(issuer)/oauth/token")!, fields: ["grant_type": "refresh_token", "refresh_token": refresh, "client_id": clientID, "scope": "openid profile email"])
        return AccountCredentials(idToken: tokens.idToken ?? credentials.idToken, accessToken: tokens.accessToken, refreshToken: tokens.refreshToken ?? credentials.refreshToken, accountID: credentials.accountID, workspaceID: credentials.workspaceID)
    }

    private func postForm(url: URL, fields: [String: String]) async throws -> OAuthTokens {
        var request = URLRequest(url: url); request.httpMethod = "POST"; request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type"); request.httpBody = fields.map { "\($0.key.urlQueryEscaped)=\($0.value.urlQueryEscaped)" }.joined(separator: "&").data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request); guard let status = (response as? HTTPURLResponse)?.statusCode, 200..<300 ~= status else { throw AccountServiceError.http((response as? HTTPURLResponse)?.statusCode ?? 0) }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any], let access = json["access_token"] as? String else { throw AccountServiceError.invalidTokenResponse }
        return OAuthTokens(idToken: json["id_token"] as? String, accessToken: access, refreshToken: json["refresh_token"] as? String)
    }

    private func record(for id: String, credentials: AccountCredentials) -> AccountRecord {
        AccountRecord(id: id, displayName: claim(credentials.idToken, key: "email") ?? id, email: claim(credentials.idToken, key: "email"), chatgptAccountID: credentials.accountID, workspaceID: credentials.workspaceID, plan: claim(credentials.idToken, key: "chatgpt_plan_type"), status: "active", usage: nil, lastRefresh: nil, lastError: nil, isCurrent: false)
    }

    private func jsonObject(at url: URL) throws -> [String: Any] { guard let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] else { throw AccountServiceError.invalidAuthFile }; return object }
    private func claim(_ token: String?, key: String) -> String? { guard let token, let part = token.split(separator: ".").dropFirst().first else { return nil }; var raw = String(part).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/"); raw += String(repeating: "=", count: (4 - raw.count % 4) % 4); guard let data = Data(base64Encoded: raw), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }; return (object[key] as? String) ?? ((object["https://api.openai.com/auth"] as? [String: Any])?[key] as? String) }
    private func randomString(byteCount: Int) -> String { Data((0..<byteCount).map { _ in UInt8.random(in: 0...255) }).base64URLEncodedString() }
    private func window(_ value: [String: Any]?) -> (remain: Double?, reset: Date?) { let used = value?["used_percent"] as? Double; let reset = (value?["reset_at"] as? Double).map(Date.init(timeIntervalSince1970:)); return (used.map { max(0, min(100, 100 - $0)) }, reset) }
}

private struct OAuthTokens { let idToken: String?; let accessToken: String; let refreshToken: String? }

private enum OAuthCallback {
    static func wait(for state: String, redirectURI: String, authorizationURL: URL) async throws -> (code: String, state: String) {
        try await withCheckedThrowingContinuation { continuation in
            let listener = try? NWListener(using: .tcp, on: 1455)
            guard let listener else { continuation.resume(throwing: AccountServiceError.callback("无法监听登录回调端口 1455。")); return }
            listener.stateUpdateHandler = { state in if case .failed(let error) = state { continuation.resume(throwing: AccountServiceError.callback(error.localizedDescription)); listener.cancel() } }
            listener.newConnectionHandler = { connection in
                guard Self.isLoopback(connection.endpoint) else { connection.cancel(); return }
                connection.start(queue: .global())
                connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, _, _ in
                    defer { connection.cancel(); listener.cancel() }
                    guard let data, let line = String(data: data, encoding: .utf8)?.split(separator: "\r\n").first,
                          let path = line.split(separator: " ").dropFirst().first,
                          let components = URLComponents(string: "http://localhost\(path)") else { continuation.resume(throwing: AccountServiceError.callback("登录回调格式无效。")); return }
                    let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
                    let response = "HTTP/1.1 200 OK\r\nContent-Type: text/plain; charset=utf-8\r\nConnection: close\r\n\r\n登录完成，请返回 CodexHistorySync。"
                    connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in })
                    guard query["state"] == state else { continuation.resume(throwing: AccountServiceError.callback("登录回调 state 校验失败。")); return }
                    if let error = query["error"], !error.isEmpty { continuation.resume(throwing: AccountServiceError.callback("登录失败：\(error)")); return }
                    guard let code = query["code"], !code.isEmpty else { continuation.resume(throwing: AccountServiceError.callback("登录回调缺少 code。")); return }
                    continuation.resume(returning: (code, state))
                }
            }
            listener.start(queue: .global()); NSWorkspace.shared.open(authorizationURL)
        }
    }

    private static func isLoopback(_ endpoint: NWEndpoint) -> Bool {
        guard case let .hostPort(host, _) = endpoint else { return false }
        return ["127.0.0.1", "::1", "localhost"].contains(host.debugDescription.lowercased())
    }
}

private extension Data { func base64URLEncodedString() -> String { base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") } }
private extension String { var urlQueryEscaped: String { addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? self } }
