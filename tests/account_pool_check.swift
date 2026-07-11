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

        let missing = try AccountUsageParser.snapshot(from: Data("{}".utf8), capturedAt: Date(timeIntervalSince1970: 2))
        precondition(missing.primaryRemainPercent == nil && missing.secondaryRemainPercent == nil)
        precondition(!WarmupResponseParser.isComplete(Data("event: response.in_progress\n".utf8)))
        precondition(WarmupResponseParser.isComplete(Data("event: response.completed\ndata: {}\n".utf8)))

        let credentials = AccountCredentials(idToken: nil, accessToken: "access", refreshToken: nil, accountID: "account", workspaceID: "workspace")
        let auth = try JSONSerialization.jsonObject(with: CodexAuthFile.directJSON(credentials: credentials, accountID: "account")) as! [String: Any]
        precondition(auth["OPENAI_API_KEY"] is NSNull)
        let tokens = auth["tokens"] as! [String: Any]
        precondition(tokens["access_token"] as? String == "access")
        precondition(tokens["id_token"] as? String == "")
        precondition(tokens["refresh_token"] as? String == "")
        print("账号池边界自检通过")
    }
}
