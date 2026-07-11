import Foundation

enum AccountServiceError: LocalizedError {
    case invalidAuthFile
    case invalidUsageResponse
    case invalidTokenResponse
    case callback(String)
    case warmupIncomplete
    case warmupFailed(String)
    case warmupHTTP(Int, String)
    case http(Int)
    case keychain(OSStatus)
    case credentialFile(String)

    var errorDescription: String? {
        switch self {
        case .invalidAuthFile: return "当前 auth.json 中没有可用的 Codex 登录 token。"
        case .invalidUsageResponse: return "额度接口返回了无法识别的数据。"
        case .invalidTokenResponse: return "登录服务返回了无效 token。"
        case .callback(let message): return message
        case .warmupIncomplete: return "预热流在完成事件前结束。"
        case .warmupFailed(let message): return "预热流失败：\(message)"
        case .warmupHTTP(let status, let message): return "预热请求失败（HTTP \(status)）：\(message)"
        case .http(let status): return "上游请求失败（HTTP \(status)）。"
        case .keychain: return "无法访问 macOS 钥匙串。"
        case .credentialFile(let message): return message
        }
    }
}
