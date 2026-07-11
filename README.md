# Codex History Sync Tool

[简体中文](README.zh-CN.md) · English

<p align="center">
  <img src="macos/Resources/Assets/AppIcon.png" width="160" alt="Codex History Sync Tool icon">
</p>

A macOS-native, backup-first tool that restores Codex Desktop conversations hidden after switching accounts, providers, models, or login methods.

> This tool changes local Codex metadata only. It does not upload conversations, sync between devices, or recover deleted files.

## Features

- Native macOS SwiftUI app for browsing and syncing selected conversations
- Native macOS SwiftUI app with a local Python backend
- Syncs provider/model metadata, session metadata, and the sidebar index
- Excludes archived conversations from listing and synchronization
- Switches between English and Simplified Chinese at runtime; localization resources are ready for more languages
- Creates a complete backup before every sync or restore
- Manages backup bundles without third-party Python dependencies

## Quick Start

### macOS app

Requirements: macOS 13+, Xcode Command Line Tools, and Python 3.10+.

```bash
git clone https://github.com/GODGOD126/codex-history-sync-tool.git
cd codex-history-sync-tool
./script/build_and_run.sh
```

The app is built locally at `dist/CodexHistorySync.app`. Select only the conversations you want, then click **Sync Selected**. Archived conversations are intentionally hidden and never changed.

### CLI

```bash
python3 sync_backend.py --json status
python3 sync_backend.py --json backup
python3 sync_backend.py --json sync
python3 sync_backend.py --json restore
```

`sync` updates every non-archived conversation that does not match the current provider/model. Use the macOS app when you want per-conversation selection.

## How It Works

Codex Desktop stores local thread metadata under `~/.codex`. After an account or provider change, old data may still exist while no longer matching the active configuration. This tool:

1. Reads the active provider/model from `config.toml`.
2. Finds non-archived mismatched threads in `state_5.sqlite` and session files.
3. Creates a SQLite-consistent database backup plus sidebar/session metadata snapshots.
4. Updates only the selected scope and rebuilds the visible sidebar index.

Backups are stored in `~/.codex/history_sync_backups`.

## Safety

- Pause active Codex responses before restoring a backup.
- Never publish your `~/.codex` directory, database, sessions, configuration, or backups.
- If the sidebar does not refresh immediately, restart Codex Desktop.
- Conversations may still be grouped by their original project directory (`cwd`). This tool does not rewrite project ownership.

## Development

```bash
python3 -m unittest discover -s tests -v
swift build
./script/build_and_run.sh --verify
```

The project uses only Python's standard library and native macOS frameworks. See [CONTRIBUTING.md](CONTRIBUTING.md) and [SECURITY.md](SECURITY.md).

Swift sources follow `App`, `Views`, `Models`, `Stores`, `Services`, `Support`, and `Resources` boundaries. To add a language, add `Resources/<language>.lproj/Localizable.strings` and register it in `AppLanguage`.

## License

[MIT](LICENSE)
