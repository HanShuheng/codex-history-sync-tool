import AppKit
import CryptoKit
import Foundation
import Network

struct AccountService: Sendable {
    let paths: AppPaths
    private let localConfig: LocalConfigStore

    private let issuer = "https://auth.openai.com"
    private let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"
    private let usageURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
    private let warmupURL = URL(string: "https://chatgpt.com/backend-api/codex/responses")!

    init(paths: AppPaths = AppPaths()) {
        self.paths = paths
        self.localConfig = LocalConfigStore(paths: paths)
    }

    func load() throws -> [AccountRecord] {
        try localConfig.load().accounts
    }

    func save(_ accounts: [AccountRecord]) throws {
        try localConfig.saveAccounts(accounts)
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
        let callback = try await OAuthCallback.wait(for: state, authorizationURL: components.url!)
        let tokens = try await exchange(code: callback.code, verifier: verifier, redirectURI: redirectURI)
        let accountID = claim(tokens.idToken, key: "chatgpt_account_id") ?? claim(tokens.accessToken, key: "chatgpt_account_id") ?? UUID().uuidString
        let credentials = AccountCredentials(idToken: tokens.idToken, accessToken: tokens.accessToken, refreshToken: tokens.refreshToken, accountID: accountID, workspaceID: claim(tokens.idToken, key: "workspace_id"))
        return (record(for: accountID, credentials: credentials), credentials)
    }

    func refresh(_ account: AccountRecord) async throws -> AccountRecord {
        guard var credentials = account.credentials else { throw AccountServiceError.credentialFile("账号凭据缺失，请重新登录。") }
        do {
            return try await withUsage(account, credentials: credentials)
        } catch AccountServiceError.http(401) where credentials.refreshToken != nil {
            credentials = try await refreshToken(credentials)
            return try await withUsage(account, credentials: credentials)
        }
    }

    func warmup(_ account: AccountRecord) async throws -> AccountRecord {
        guard var credentials = account.credentials else { throw AccountServiceError.credentialFile("账号凭据缺失，请重新登录。") }
        do {
            try await sendWarmup(credentials)
        } catch AccountServiceError.http(401) where credentials.refreshToken != nil {
            credentials = try await refreshToken(credentials); try await sendWarmup(credentials)
        }
        return try await withUsage(account, credentials: credentials)
    }

    func switchTo(_ account: AccountRecord) async throws -> AccountRecord {
        guard var credentials = account.credentials else { throw AccountServiceError.credentialFile("账号凭据缺失，请重新登录。") }
        if credentials.refreshToken != nil {
            credentials = try await refreshToken(credentials)
        }
        let originalAuth = FileManager.default.fileExists(atPath: paths.auth.path) ? try String(contentsOf: paths.auth, encoding: .utf8) : nil
        let originalConfig = FileManager.default.fileExists(atPath: paths.config.path) ? try String(contentsOf: paths.config, encoding: .utf8) : nil
        try saveProfileBackupIfNeeded(authJSON: originalAuth, configTOML: originalConfig)
        let data = try CodexAuthFile.directJSON(credentials: credentials, accountID: account.id)
        let config = CodexAuthFile.directConfig(from: originalConfig)
        do {
            try writeAtomically(data, to: paths.auth)
            try writeAtomically(Data(config.utf8), to: paths.config)
            guard ((try? jsonObject(at: paths.auth)["tokens"] as? [String: Any])?["access_token"] as? String) == credentials.accessToken else { throw AccountServiceError.invalidAuthFile }
        } catch {
            restore(originalAuth, to: paths.auth)
            restore(originalConfig, to: paths.config)
            throw error
        }
        var updated = account
        updated.credentials = credentials
        return updated
    }

    private func saveProfileBackupIfNeeded(authJSON: String?, configTOML: String?) throws {
        guard !FileManager.default.fileExists(atPath: paths.profileBackup.path) else { return }
        try FileManager.default.createDirectory(at: paths.accountBackupDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try writeAtomically(encoder.encode(CodexProfileBackup(authJSON: authJSON, configTOML: configTOML)), to: paths.profileBackup)
    }

    private func writeAtomically(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func restore(_ content: String?, to url: URL) {
        guard let content else { try? FileManager.default.removeItem(at: url); return }
        try? writeAtomically(Data(content.utf8), to: url)
    }

    private func withUsage(_ account: AccountRecord, credentials: AccountCredentials) async throws -> AccountRecord {
        var request = URLRequest(url: usageURL); request.httpMethod = "GET"; request.timeoutInterval = 30
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        if let id = credentials.workspaceID ?? credentials.accountID ?? account.workspaceID ?? account.chatgptAccountID { request.setValue(id, forHTTPHeaderField: "ChatGPT-Account-ID") }
        request.setValue("codex_cli_rs/0.102.1", forHTTPHeaderField: "User-Agent")
        request.setValue("codex_cli_rs", forHTTPHeaderField: "originator")
        request.setValue("https://chatgpt.com", forHTTPHeaderField: "Origin")
        request.setValue("https://chatgpt.com/", forHTTPHeaderField: "Referer")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let status = (response as? HTTPURLResponse)?.statusCode, 200..<300 ~= status else { throw AccountServiceError.http((response as? HTTPURLResponse)?.statusCode ?? 0) }
        var updated = account; updated.credentials = credentials; updated.usage = try AccountUsageParser.snapshot(from: data); updated.lastRefresh = updated.usage?.capturedAt; updated.lastError = nil; updated.status = "active"; return updated
    }

    private func sendWarmup(_ credentials: AccountCredentials) async throws {
        var request = URLRequest(url: warmupURL); request.httpMethod = "POST"; request.timeoutInterval = 90
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization"); request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://chatgpt.com", forHTTPHeaderField: "Origin"); request.setValue("https://chatgpt.com/", forHTTPHeaderField: "Referer")
        if let accountID = credentials.workspaceID ?? credentials.accountID { request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-ID") }
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("codex_cli_rs/0.102.1", forHTTPHeaderField: "User-Agent")
        request.setValue("codex_cli_rs", forHTTPHeaderField: "originator")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["model": "gpt-5.3-codex", "instructions": "", "input": [["type": "message", "role": "user", "content": [["type": "input_text", "text": "hi"]]]], "stream": true, "store": false], options: [])
        let (data, response) = try await URLSession.shared.data(for: request); guard let status = (response as? HTTPURLResponse)?.statusCode, 200..<300 ~= status else { throw AccountServiceError.http((response as? HTTPURLResponse)?.statusCode ?? 0) }
        guard WarmupResponseParser.isComplete(data) else { throw AccountServiceError.warmupIncomplete }
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
        AccountRecord(id: id, displayName: claim(credentials.idToken, key: "email") ?? id, email: claim(credentials.idToken, key: "email"), chatgptAccountID: credentials.accountID, workspaceID: credentials.workspaceID, plan: claim(credentials.idToken, key: "chatgpt_plan_type"), status: "active", usage: nil, lastRefresh: nil, lastError: nil, isCurrent: false, credentials: credentials)
    }

    private func jsonObject(at url: URL) throws -> [String: Any] { guard let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] else { throw AccountServiceError.invalidAuthFile }; return object }
    private func claim(_ token: String?, key: String) -> String? { guard let token, let part = token.split(separator: ".").dropFirst().first else { return nil }; var raw = String(part).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/"); raw += String(repeating: "=", count: (4 - raw.count % 4) % 4); guard let data = Data(base64Encoded: raw), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }; return (object[key] as? String) ?? ((object["https://api.openai.com/auth"] as? [String: Any])?[key] as? String) }
    private func randomString(byteCount: Int) -> String { Data((0..<byteCount).map { _ in UInt8.random(in: 0...255) }).base64URLEncodedString() }
}

private struct OAuthTokens { let idToken: String?; let accessToken: String; let refreshToken: String? }

private enum OAuthCallback {
    static func wait(for state: String, authorizationURL: URL) async throws -> (code: String, state: String) {
        try await withCheckedThrowingContinuation { continuation in
            let gate = OAuthCallbackGate()
            let listener = try? NWListener(using: .tcp, on: 1455)
            guard let listener else { gate.run { continuation.resume(throwing: AccountServiceError.callback("无法监听登录回调端口 1455。")) }; return }
            listener.stateUpdateHandler = { state in if case .failed(let error) = state { gate.run { continuation.resume(throwing: AccountServiceError.callback(error.localizedDescription)) }; listener.cancel() } }
            listener.newConnectionHandler = { connection in
                guard Self.isLoopback(connection.endpoint) else { connection.cancel(); return }
                connection.start(queue: .global())
                connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, _, _ in
                    defer { connection.cancel(); listener.cancel() }
                    guard let data, let line = String(data: data, encoding: .utf8)?.split(separator: "\r\n").first,
                          let path = line.split(separator: " ").dropFirst().first,
                          let components = URLComponents(string: "http://localhost\(path)") else { gate.run { continuation.resume(throwing: AccountServiceError.callback("登录回调格式无效。")) }; return }
                    let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
                    let response = "HTTP/1.1 200 OK\r\nContent-Type: text/plain; charset=utf-8\r\nConnection: close\r\n\r\n登录完成，请返回 CodexHistorySync。"
                    connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in })
                    guard query["state"] == state else { gate.run { continuation.resume(throwing: AccountServiceError.callback("登录回调 state 校验失败。")) }; return }
                    if let error = query["error"], !error.isEmpty { gate.run { continuation.resume(throwing: AccountServiceError.callback("登录失败：\(error)")) }; return }
                    guard let code = query["code"], !code.isEmpty else { gate.run { continuation.resume(throwing: AccountServiceError.callback("登录回调缺少 code。")) }; return }
                    gate.run { continuation.resume(returning: (code, state)) }
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
