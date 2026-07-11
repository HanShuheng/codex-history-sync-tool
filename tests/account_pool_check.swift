import Foundation

@main
struct AccountPoolCheck {
    static func main() throws {
        let data = Data("""
        {"rate_limit":{"primary_window":{"used_percent":0,"reset_at":1700000000},"secondary_window":{"used_percent":"100","reset_at":1700000100.5}}}
        """.utf8)
        let snapshot = try AccountUsageParser.snapshot(from: data, capturedAt: Date(timeIntervalSince1970: 1))
        precondition(snapshot.primaryRemainPercent == 100)
        precondition(snapshot.secondaryRemainPercent == 0)
        precondition(snapshot.primaryResetsAt?.timeIntervalSince1970 == 1700000000)
        precondition(snapshot.secondaryResetsAt?.timeIntervalSince1970 == 1700000100.5)

        let models = CodexModelCatalog.parse(Data("""
        {"models":[
          {"slug":"gpt-hidden","display_name":"Hidden","visibility":"hidden"},
          {"slug":"gpt-unsupported","supported_in_api":false},
          {"slug":"gpt-first","supported_in_api":true,"visibility":"list"},
          {"slug":"gpt-second","supported_in_api":true,"visibility":"list"}
        ]}
        """.utf8))
        precondition(CodexModelCatalog.selectPreferredModel(from: models) == "gpt-first")
        precondition(CodexModelCatalog.selectPreferredModel(from: CodexModelCatalog.parse(Data("{\"data\":[{\"id\":\"legacy-model\"}]}".utf8))) == "legacy-model")
        precondition(CodexModelCatalog.selectPreferredModel(from: CodexModelCatalog.parse(Data("{\"models\":[{\"slug\":\"hidden\",\"visibility\":\"hidden\"}]}".utf8))) == nil)

        let missing = try AccountUsageParser.snapshot(from: Data("{}".utf8), capturedAt: Date(timeIntervalSince1970: 2))
        precondition(missing.primaryRemainPercent == nil && missing.secondaryRemainPercent == nil)
        precondition(!WarmupResponseParser.isComplete(Data("event: response.in_progress\n".utf8)))
        precondition(WarmupResponseParser.isComplete(Data("event: response.completed\ndata: {}\n".utf8)))
        precondition(WarmupResponseParser.isComplete(Data("event: response.done\ndata: {}\n".utf8)))
        precondition(WarmupResponseParser.isComplete(Data("data: [DONE]\n".utf8)))
        do {
            try WarmupResponseParser.validate(Data("event: response.failed\ndata: {\"error\":{\"message\":\"quota exceeded\"}}\n".utf8))
            preconditionFailure("错误事件应该失败")
        } catch AccountServiceError.warmupFailed(let message) {
            precondition(message == "quota exceeded")
        }

        let credentials = AccountCredentials(idToken: nil, accessToken: "access", refreshToken: nil, accountID: "account", workspaceID: "workspace")
        let auth = try JSONSerialization.jsonObject(with: CodexAuthFile.directJSON(credentials: credentials, accountID: "account")) as! [String: Any]
        precondition(auth["OPENAI_API_KEY"] is NSNull)
        let tokens = auth["tokens"] as! [String: Any]
        precondition(tokens["access_token"] as? String == "access")
        precondition(tokens["id_token"] as? String == "")
        precondition(tokens["refresh_token"] as? String == "")

        let account = AccountRecord(id: "account", displayName: "account", email: nil, chatgptAccountID: "account", workspaceID: "workspace", plan: nil, status: "active", usage: nil, lastRefresh: nil, lastError: nil, isCurrent: false, credentials: credentials)
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let paths = AppPaths(codexHome: home, appHome: home.appendingPathComponent("codexhistorysync"))
        let localConfig = LocalConfigStore(paths: paths)
        try localConfig.saveAccounts([account])
        try localConfig.saveSelectedThreadIDs(["thread"])
        let saved = try localConfig.load()
        precondition(saved.accounts.first?.credentials?.accessToken == "access")
        precondition(saved.selectedThreadIDs == ["thread"])
        let permissions = try FileManager.default.attributesOfItem(atPath: paths.appConfig.path)[.posixPermissions] as? NSNumber
        precondition(permissions?.intValue == 0o600)
        try? FileManager.default.removeItem(at: home)

        let directConfig = CodexAuthFile.directConfig(from: "model_provider = \"cm\"\nmodel = \"gpt-5\"\n\n[model_providers.cm]\nbase_url = \"http://localhost\"\n\n[model_providers.other]\nname = \"Other\"\n")
        precondition(!directConfig.contains("model_provider = \"cm\""))
        precondition(!directConfig.contains("[model_providers.cm]"))
        precondition(directConfig.contains("[model_providers.other]"))

        let gate = OAuthCallbackGate()
        let counterLock = NSLock()
        var callbackCount = 0
        DispatchQueue.concurrentPerform(iterations: 100) { _ in
            gate.run {
                counterLock.lock(); callbackCount += 1; counterLock.unlock()
            }
        }
        precondition(callbackCount == 1)
        print("账号池边界自检通过")
    }
}
