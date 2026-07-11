# Codex 历史同步工具

简体中文 · [English](README.md)

<p align="center">
  <img src="macos/Resources/Assets/AppIcon.png" width="160" alt="Codex 历史同步工具图标">
</p>

一个原生 macOS、备份优先的小工具，用于找回因切换账号、Provider、模型或登录方式而在 Codex Desktop 侧边栏中消失的历史对话。

> 本工具只修改本机 Codex 元数据，不会上传对话、跨设备同步，也无法恢复已经删除的文件。

## 功能

- 原生 macOS SwiftUI 应用，可按项目浏览并选择性同步历史
- 原生 macOS SwiftUI 应用与本地 Python 后端
- 同步数据库、会话元数据和侧边栏索引中的 Provider/模型归属
- 归档对话不展示、不参与同步
- 支持在应用内切换简体中文与英文，并预留其他语言扩展入口
- 每次同步或恢复前自动创建完整备份
- 可管理成组备份，无第三方 Python 依赖

## 快速开始

### macOS 应用

要求：macOS 13+、Xcode Command Line Tools、Python 3.10+。

```bash
git clone https://github.com/GODGOD126/codex-history-sync-tool.git
cd codex-history-sync-tool
./script/build_and_run.sh
```

应用会构建到 `dist/CodexHistorySync.app`。勾选需要恢复的对话，再点击“同步所选”。归档对话会被隐藏且不会被修改。

### 命令行

```bash
python3 sync_backend.py --json status   # 查看状态
python3 sync_backend.py --json backup   # 手动备份
python3 sync_backend.py --json sync     # 同步全部非归档历史
python3 sync_backend.py --json restore  # 恢复最新备份
```

需要逐条选择时，请使用 macOS 图形界面。

## 工作原理

Codex Desktop 把本地线程元数据保存在 `~/.codex`。切换账号或 Provider 后，旧数据可能仍在磁盘上，但归属与当前配置不一致。本工具会：

1. 从 `config.toml` 读取当前 Provider 和模型。
2. 在 `state_5.sqlite` 与会话文件中找出未归档且归属不一致的线程。
3. 使用 SQLite Backup API 备份数据库，并保存侧边栏索引与会话首行元数据。
4. 只修改选定范围，然后重建可见侧边栏索引。

备份默认保存在 `~/.codex/history_sync_backups`。

## 安全说明

- 恢复备份前，请先暂停正在生成回复的 Codex 任务。
- 不要公开上传 `~/.codex`、数据库、会话记录、配置或备份。
- 如果侧边栏没有立即刷新，请重启 Codex Desktop。
- Codex 可能仍按原项目目录（`cwd`）分组历史；本工具不会批量改写项目归属。

## 开发

```bash
python3 -m unittest discover -s tests -v
swift build
./script/build_and_run.sh --verify
```

项目只使用 Python 标准库和 macOS 原生框架。贡献与安全报告方式见 [CONTRIBUTING.md](CONTRIBUTING.md) 和 [SECURITY.md](SECURITY.md)。

Swift 源码按 `App`、`Views`、`Models`、`Stores`、`Services`、`Support` 和 `Resources` 分层。新增语言时，只需添加 `Resources/<语言>.lproj/Localizable.strings` 并在 `AppLanguage` 中注册。

## 许可证

[MIT](LICENSE)
