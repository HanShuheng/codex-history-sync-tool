import Foundation

struct CodexAvailableModel: Hashable, Sendable {
    let slug: String
    let displayName: String
    let supportedInAPI: Bool
    let visibility: String?
    let sortIndex: Int
    let updatedAt: Int64
}

enum CodexModelCatalog {
    static let clientVersion = "0.102.1"
    private static let endpoint = URL(string: "https://chatgpt.com/backend-api/codex/models")!
    private static let hiddenVisibilities = Set(["hide", "hidden", "disabled", "unavailable"])

    static func fetch(account: AccountRecord, credentials: AccountCredentials) async throws -> [CodexAvailableModel] {
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "client_version", value: clientVersion)]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("codex_cli_rs/\(clientVersion)", forHTTPHeaderField: "User-Agent")
        request.setValue("codex_cli_rs", forHTTPHeaderField: "originator")
        if let accountID = credentials.workspaceID ?? credentials.accountID ?? account.workspaceID ?? account.chatgptAccountID {
            request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-ID")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard 200..<300 ~= status else { throw AccountServiceError.modelCatalogHTTP(status) }
        let models = parse(data)
        guard !models.isEmpty else { throw AccountServiceError.modelCatalogEmpty }
        return models
    }

    // 模型目录目前没有稳定的 token 价格字段，按服务端目录顺序选择可用模型。
    static func selectPreferredModel(from models: [CodexAvailableModel]) -> String? {
        models
            .filter { model in
                model.supportedInAPI &&
                    !model.slug.isEmpty &&
                    !hiddenVisibilities.contains(model.visibility?.lowercased() ?? "")
            }
            .sorted {
                ($0.sortIndex, -$0.updatedAt, $0.slug) < ($1.sortIndex, -$1.updatedAt, $1.slug)
            }
            .first?.slug
    }

    static func parse(_ data: Data) -> [CodexAvailableModel] {
        guard let root = try? JSONSerialization.jsonObject(with: data) else { return [] }
        let values: [Any]
        if let object = root as? [String: Any], let models = object["models"] as? [Any], !models.isEmpty {
            values = models
        } else if let object = root as? [String: Any], let items = object["items"] as? [Any], !items.isEmpty {
            values = items
        } else if let object = root as? [String: Any], let data = object["data"] as? [Any] {
            values = data
        } else {
            values = (root as? [Any]) ?? []
        }

        var seen = Set<String>()
        return values.enumerated().compactMap { index, value in
            guard let object = value as? [String: Any],
                  let rawSlug = (object["slug"] as? String) ?? (object["id"] as? String) else { return nil }
            let slug = rawSlug.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !slug.isEmpty, seen.insert(slug).inserted else { return nil }
            let displayName = ((object["display_name"] as? String) ?? (object["displayName"] as? String) ?? slug)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let supported = (object["supported_in_api"] as? Bool) ?? (object["supportedInAPI"] as? Bool) ?? true
            let visibility = (object["visibility"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let sortIndex = (object["sort_index"] as? Int) ?? (object["sortIndex"] as? Int) ?? index
            let updatedAt = (object["updated_at"] as? Int64) ?? (object["updatedAt"] as? Int64) ?? 0
            return CodexAvailableModel(slug: slug, displayName: displayName.isEmpty ? slug : displayName, supportedInAPI: supported, visibility: visibility, sortIndex: sortIndex, updatedAt: updatedAt)
        }
    }
}
