# Codex-Manager 功能分析

调研对象：[qxcnm/Codex-Manager](https://github.com/qxcnm/Codex-Manager)，默认分支 `main`，调研日期 2026-07-11。

## 总体架构

Codex-Manager 是 Tauri 前端 + 本地 Rust service + SQLite storage。账号功能不是单个页面逻辑，而是：

```text
SwiftUI/前端页面
    -> API/RPC 客户端
    -> service RPC dispatch
    -> account/auth/usage domain
    -> SQLite 账号、token、usage snapshot
    -> Codex/OpenAI OAuth 或上游 HTTP
```

本项目没有 Rust service，采用同样的职责边界但用 macOS 原生组件替代：SwiftUI 页面 -> `BackendClient` -> Service -> Keychain/JSON/URLSession -> OpenAI。

## 账号模型和额度模型

关键类型见 [`apps/src/types/account.ts`](https://github.com/qxcnm/Codex-Manager/blob/main/apps/src/types/account.ts)：

- `Account` 同时包含账号身份、状态、套餐、token 是否存在、可用性、两个窗口剩余百分比和 usage 快照。
- `AccountUsage` 使用 `usedPercent`、`windowMinutes`、`resetsAt` 表示主窗口，使用 `secondaryUsedPercent`、`secondaryWindowMinutes`、`secondaryResetsAt` 表示次窗口。
- 前端用 `primaryRemainPercent`/`secondaryRemainPercent` 展示剩余量，不能把 used 和 remain 混为一谈。

服务端账号列表入口是 [`crates/service/src/account/account_list.rs`](https://github.com/qxcnm/Codex-Manager/blob/main/crates/service/src/account/account_list.rs)，它把账号、token/套餐、元数据、订阅信息和 usage snapshot 合并成一条列表数据。元数据的存取在 [`crates/core/src/storage/account_metadata.rs`](https://github.com/qxcnm/Codex-Manager/blob/main/crates/core/src/storage/account_metadata.rs)。

## 登录实现

登录入口：

- 前端调用见 [`apps/src/lib/api/account-client.ts`](https://github.com/qxcnm/Codex-Manager/blob/main/apps/src/lib/api/account-client.ts) 的 `startLogin`、`getLoginStatus`、`completeLogin`。
- Rust 登录启动见 [`crates/service/src/auth/auth_login.rs`](https://github.com/qxcnm/Codex-Manager/blob/main/crates/service/src/auth/auth_login.rs)。
- OAuth 常量、PKCE、state 和 JWT claim 提取见 [`crates/core/src/auth/mod.rs`](https://github.com/qxcnm/Codex-Manager/blob/main/crates/core/src/auth/mod.rs)。
- 本机回调 HTTP server 和 redirect URI 见 [`crates/service/src/auth/auth_callback.rs`](https://github.com/qxcnm/Codex-Manager/blob/main/crates/service/src/auth/auth_callback.rs)。
- code 换 token、refresh token 和 token 持久化见 [`crates/service/src/auth/auth_tokens.rs`](https://github.com/qxcnm/Codex-Manager/blob/main/crates/service/src/auth/auth_tokens.rs)。

实现要点：

1. 生成 PKCE verifier/challenge 和随机 state。
2. 保存待完成登录会话，打开授权 URL。
3. 回调验证 state 后，将 authorization code 发送到 token endpoint。
4. 从 id token/access token claim 提取账号 ID、workspace、邮箱和套餐。
5. 持久化 token，并由页面轮询登录状态。

## 额度查询实现

HTTP 细节集中在 [`crates/service/src/usage/usage_http.rs`](https://github.com/qxcnm/Codex-Manager/blob/main/crates/service/src/usage/usage_http.rs)：

- 使用 Bearer access token 调用 usage endpoint。
- 通过 `ChatGPT-Account-ID`、workspace 和 residency 等账号上下文 header 选择正确账号。
- 读取主窗口与次窗口的 used percentage、窗口长度和 reset timestamp。
- access token 失效时先用 refresh token 换新 token，再重试 usage 请求。
- HTTP client 有连接/总超时，并复用连接；错误信息需要脱敏。

本项目复用这些行为，但只保留第一版需要的 URLSession、超时、header、refresh 重试和脱敏错误。

## 预热实现

核心文件是 [`crates/service/src/account/account_warmup.rs`](https://github.com/qxcnm/Codex-Manager/blob/main/crates/service/src/account/account_warmup.rs)：

- `warmup_accounts(account_ids, message)` 解析目标账号；空列表表示全部可用账号。
- 默认消息为 `hi`，默认模型为 `gpt-5.3-codex`。
- 请求地址为 `https://chatgpt.com/backend-api/codex/responses`。
- 每个账号单独执行；成功/失败聚合为 `requested/succeeded/failed/results`。
- token 相关失败会先 refresh token，再重试一次。
- 成功后调用 usage refresh，把预热后的真实窗口数据重新写回存储。

因此“预热后 5 小时额度刷新”不是本地把时间改成当前时间，而是让上游产生一次真实请求，然后重新读取上游 usage 响应。若上游策略未变化，界面必须如实显示原 reset 时间。

## 直连切换和当前账号

Codex-Manager 的账号相关 RPC 集中在 [`crates/service/src/rpc_dispatch/account.rs`](https://github.com/qxcnm/Codex-Manager/blob/main/crates/service/src/rpc_dispatch/account.rs)，同时提供 `account/read`、`account/logout`、登录、token refresh 等入口。账号列表页面 [`apps/src/app/accounts/accounts-page-view.tsx`](https://github.com/qxcnm/Codex-Manager/blob/main/apps/src/app/accounts/accounts-page-view.tsx) 提供添加、刷新、预热和选择操作。

对于本项目，“账号直连切换”的最小等价实现是：

- 账号池保存每个账号的认证材料；
- 切换时读取目标账号的 token；
- 原子备份并替换当前 `~/.codex/auth.json`；
- 以 `last_refresh` 和当前账号身份重新加载界面。

这比实现 Codex-Manager 的完整 gateway/session routing 小，但满足桌面端直接切换 Codex 当前登录账号的需求。

## 调研结论和取舍

| Codex-Manager 能力 | 本项目实现 |
| --- | --- |
| SQLite 账号/usage/metadata 多表 | 非敏感元数据与快照 JSON；token 使用 Keychain |
| Tauri RPC | `BackendClient` + Swift Service |
| OAuth PKCE + localhost callback | `ASWebAuthenticationSession` 或本机回调 URLSession server |
| usage HTTP + refresh retry | Foundation `URLSession` |
| Responses 预热 + usage refresh | Foundation `URLSession`，逐账号执行 |
| gateway 自动轮换 | 不实现；只做当前 auth.json 直连切换 |

参考代码足以定位具体实现：先看 `account-client.ts` 的操作契约，再看 `rpc_dispatch/account.rs` 的路由，最后分别进入 `auth_login.rs`、`auth_tokens.rs`、`usage_http.rs` 和 `account_warmup.rs`。
