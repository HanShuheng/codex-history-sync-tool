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

本项目没有 Rust service，采用同样的职责边界但用 macOS 原生组件替代：SwiftUI 页面 -> `BackendClient` -> Service -> 本地 JSON/URLSession -> OpenAI。

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
- 默认消息为 `hi`。模型先从 Codex 模型目录获取，不使用已过时的硬编码模型。
- 请求地址为 `https://chatgpt.com/backend-api/codex/responses`。
- 每个账号单独执行；成功/失败聚合为 `requested/succeeded/failed/results`。
- token 相关失败会先 refresh token，再重试一次。
- 成功后调用 usage refresh，把预热后的真实窗口数据重新写回存储。

模型选择的关键细节：Codex-Manager 先访问其 Codex 上游的模型目录，过滤 `supported_in_api=false`、空 slug 和 `hide/hidden/disabled/unavailable` 模型，再按 `sort_index ASC, updated_at DESC, slug ASC` 取第一项。模型目录没有稳定的 token 消耗字段，因此这代表“目录优先级最高的可用模型”，不能严谨地宣称是 token 成本最低模型。

因此“预热后 5 小时额度刷新”不是本地把时间改成当前时间，而是让上游产生一次真实请求，然后重新读取上游 usage 响应。若上游策略未变化，界面必须如实显示原 reset 时间。

需要区分“Responses 请求完成”和“账号仍有额度”：前者只能证明上游接受并完成了请求，不能证明 5 小时/7 天窗口有剩余额度。若 usage 返回剩余额度为 0，本项目会把预热标记为失败并提示等待窗口刷新。

## 直连切换和当前账号

Codex-Manager 的 profile 直连切换不是普通的账号列表按钮，而是一个完整的 profile 接管流程。真实代码位置如下：

1. 前端入口：`apps/src/app/platform-mode/use-platform-mode-state.ts:160-174` 调用 `applyDirectAccount({ accountId, codexHome })`；成功后刷新状态并提示切换完成。
2. 前端 RPC：`apps/src/lib/api/codex-profile-client.ts:255-266` 调用 `service_codex_profile_apply_direct_account`。
3. RPC 路由：`crates/service/src/rpc_dispatch/codex_profile.rs:25-30` 转发到 `crate::codex_profile::apply_direct_account`。
4. 核心流程：`crates/service/src/codex_profile.rs:284-339`，依次解析 profile、读取账号、检查 active、读取 token、刷新 token、备份、生成 auth、修补 config、写文件和刷新状态。
5. 账号与 token 查询：`crates/core/src/storage/accounts.rs:572-588` 的 `find_account_direct_auth_profile_by_id`；token 查询和更新在 `crates/core/src/storage/tokens.rs` 的 `find_token_by_account_id`、`insert_token` 及 refresh schedule 方法。
6. auth 结构：`crates/service/src/codex_profile.rs:1715-1737` 的 `build_direct_auth_json`。
7. config 修补：`crates/service/src/codex_profile.rs:1748-1778` 的 `patch_config_for_direct`，只删除 Codex-Manager 自己的 `cm` provider，不删除其他 provider。
8. 原子写入：`crates/service/src/codex_profile.rs:1808-1838` 的 `write_profile_files` 和 `1925-1940` 的 `write_atomic`，同时写 `auth.json`、`config.toml` 和 managed marker。
9. 首次备份：`crates/service/src/codex_profile.rs:1840-1868` 的 `ensure_backup`，备份按 profile key 保存到 service 的持久化设置中，只生成一次。
10. 回滚：`crates/service/src/codex_profile.rs:391-418` 的 `restore`，恢复原 auth/config，并清理 marker 和备份状态。

### Codex-Manager 的实际切换顺序

```text
accountId/codexHome
  -> resolve_profile_dir + ensure_profile_dir_valid
  -> find_account_direct_auth_profile_by_id
  -> 检查 account.status == active
  -> find_token_by_account_id
  -> ensure_usable_token
  -> refresh_and_persist_access_token
  -> ensure_backup（仅首次）
  -> build_direct_auth_json
  -> patch_config_for_direct
  -> write_profile_files（auth/config/marker 原子写入）
  -> persist_codex_home
  -> status_for_profile_with_history_repair
```

因此本项目不能只写 `auth.json`。等价实现必须至少保留：token 刷新、首次备份、`cm` provider 清理、双文件失败回滚、切换后重启提示。网关轮换和 Codex-Manager 的 SQLite/RPC 体系不属于本项目范围。

## 调研结论和取舍

| Codex-Manager 能力 | 本项目实现 |
| --- | --- |
| SQLite 账号/usage/metadata 多表 | `~/.codexhistorysync/config.json` 的 `accounts` 与 `selected_thread_ids` 字段 |
| Tauri RPC | `BackendClient` + Swift Service |
| OAuth PKCE + localhost callback | `ASWebAuthenticationSession` 或本机回调 URLSession server |
| usage HTTP + refresh retry | Foundation `URLSession` |
| Responses 预热 + usage refresh | Foundation `URLSession`，逐账号执行 |
| profile 接管、auth/config 双文件写入 | 实现首次备份、`cm` provider 清理、双文件回滚和当前账号标记 |
| gateway 自动轮换 | 不实现；只做当前 auth.json 直连切换 |

参考代码足以定位具体实现：先看 `account-client.ts` 的操作契约，再看 `rpc_dispatch/account.rs` 的路由，最后分别进入 `auth_login.rs`、`auth_tokens.rs`、`usage_http.rs` 和 `account_warmup.rs`。
