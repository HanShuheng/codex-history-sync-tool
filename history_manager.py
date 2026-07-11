from __future__ import annotations

import argparse
import json
import sqlite3
from datetime import datetime
from pathlib import Path

from sync_backend import (
    connect_db,
    ensure_environment,
    make_backup,
    parse_current_model,
    parse_current_provider,
    read_text,
    rebuild_session_index,
    resolve_paths,
    scan_session_records,
    split_first_line,
    to_json,
    write_text_exact,
)

SELECTIONS_FILE = "history_manager_selections.json"
BACKUP_SUFFIXES = ("", ".session_index.jsonl", ".session_meta.json")


def _global_state_path(codex_home: Path) -> Path:
    return codex_home / ".codex-global-state.json"


def read_pinned_ids(codex_home: Path) -> set[str]:
    path = _global_state_path(codex_home)
    if not path.exists():
        return set()
    try:
        state = json.loads(read_text(path))
    except (OSError, json.JSONDecodeError):
        return set()
    value = state.get("pinned-thread-ids", [])
    return {str(item) for item in value} if isinstance(value, list) else set()


def selection_path(codex_home: Path) -> Path:
    return codex_home / SELECTIONS_FILE


def read_selections(codex_home: Path) -> set[str]:
    path = selection_path(codex_home)
    if not path.exists():
        return set()
    try:
        value = json.loads(read_text(path))
        return {str(item) for item in value.get("selected_thread_ids", [])}
    except (OSError, json.JSONDecodeError, AttributeError):
        return set()


def save_selections(codex_home: Path, thread_ids: list[str]) -> dict[str, object]:
    unique_ids = sorted(set(thread_ids))
    selection_path(codex_home).write_text(
        json.dumps({"selected_thread_ids": unique_ids}, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    return {"selected_count": len(unique_ids)}


def display_title(value: object, fallback: str, limit: int = 240) -> str:
    title = " ".join(str(value or fallback).split())
    return title if len(title) <= limit else title[: limit - 1] + "…"


def list_threads(codex_home: str | None = None) -> dict[str, object]:
    paths = resolve_paths(codex_home)
    ensure_environment(paths)
    config = read_text(paths.config_path)
    pinned_ids = read_pinned_ids(paths.codex_home)
    selected_ids = read_selections(paths.codex_home)
    current_provider = parse_current_provider(config)
    current_model = parse_current_model(config)

    with connect_db(paths.db_path, readonly=True) as conn:
        columns = {str(row["name"]) for row in conn.execute("PRAGMA table_info(threads)")}
        archived_column = "archived" if "archived" in columns else "0 AS archived"
        rows = conn.execute(
            f"""
            SELECT id, title, cwd, model_provider, model, {archived_column}, updated_at
            FROM threads
            {"WHERE archived = 0" if "archived" in columns else ""}
            ORDER BY cwd COLLATE NOCASE, updated_at DESC, id
            """
        ).fetchall()

    threads = []
    for row in rows:
        provider = str(row["model_provider"] or "")
        model = str(row["model"] or "")
        thread_id = str(row["id"])
        is_current = provider == current_provider and (not current_model or model == current_model)
        threads.append(
            {
                "id": thread_id,
                "title": display_title(row["title"], thread_id),
                "project": str(row["cwd"] or "未归属项目"),
                "provider": provider or "(empty)",
                "model": model or "(empty)",
                "archived": bool(row["archived"]),
                "pinned": thread_id in pinned_ids,
                "selected": thread_id in selected_ids,
                "is_current": is_current,
                "updated_at": datetime.fromtimestamp(int(row["updated_at"])).isoformat(timespec="seconds"),
            }
        )
    return {
        "current_provider": current_provider,
        "current_model": current_model,
        "threads": threads,
        "selected_count": len(selected_ids),
    }


def sync_selected(codex_home: str | None, thread_ids: list[str]) -> dict[str, object]:
    paths = resolve_paths(codex_home)
    requested = sorted(set(thread_ids))
    if not requested:
        raise RuntimeError("请至少选择一条历史记录。")
    config = read_text(paths.config_path)
    provider = parse_current_provider(config)
    model = parse_current_model(config)
    backup_path = make_backup(paths, "pre-selected-sync")
    placeholders = ",".join("?" for _ in requested)

    with connect_db(paths.db_path) as conn:
        columns = {str(row["name"]) for row in conn.execute("PRAGMA table_info(threads)")}
        set_sql = "model_provider = ?"
        params: list[object] = [provider]
        if model and "model" in columns:
            set_sql += ", model = ?"
            params.append(model)
        params.extend(requested)
        archived_guard = " AND archived = 0" if "archived" in columns else ""
        active_ids = {str(row["id"]) for row in conn.execute(
            f"SELECT id FROM threads WHERE id IN ({placeholders}){archived_guard}", requested
        )}
        updated_rows = conn.execute(
            f"UPDATE threads SET {set_sql} WHERE id IN ({placeholders}){archived_guard}",
            params,
        ).rowcount
        conn.commit()

    # 会话文件只改所选 thread id，正文保持不动。
    selected_records = {record.thread_id: record for record in scan_session_records(paths)}
    updated_sessions = 0
    for thread_id in sorted(active_ids):
        record = selected_records.get(thread_id)
        if not record:
            continue
        text = record.path.read_text(encoding="utf-8")
        first_line, ending, remainder = split_first_line(text)
        item = json.loads(first_line)
        payload = item["payload"]
        payload["model_provider"] = provider
        if model:
            payload["model"] = model
        new_first_line = json.dumps(item, ensure_ascii=False, separators=(",", ":"))
        write_text_exact(record.path, new_first_line + ending + remainder)
        updated_sessions += 1

    with connect_db(paths.db_path, readonly=True) as conn:
        rebuild_session_index(paths, conn)
    save_selections(paths.codex_home, sorted(active_ids))
    return {
        "updated_rows": updated_rows,
        "updated_session_files": updated_sessions,
        "backup_path": str(backup_path),
        "selected_count": len(active_ids),
    }


def backup_items(codex_home: str | None = None) -> dict[str, object]:
    paths = resolve_paths(codex_home)
    items = []
    for database in sorted(paths.backup_dir.glob("state_5.sqlite.*.bak"), key=lambda p: p.stat().st_mtime, reverse=True):
        bundle = [Path(str(database) + suffix) for suffix in BACKUP_SUFFIXES]
        size = sum(path.stat().st_size for path in bundle if path.exists())
        items.append(
            {
                "name": database.name,
                "path": str(database),
                "size_bytes": size,
                "modified_at": datetime.fromtimestamp(database.stat().st_mtime).isoformat(timespec="seconds"),
            }
        )
    return {"backups": items, "total_size_bytes": sum(int(item["size_bytes"]) for item in items)}


def delete_backups(codex_home: str | None, names: list[str]) -> dict[str, object]:
    paths = resolve_paths(codex_home)
    allowed = {path.name for path in paths.backup_dir.glob("state_5.sqlite.*.bak")}
    requested = sorted(set(names))
    invalid = [name for name in requested if name not in allowed or Path(name).name != name]
    if invalid:
        raise RuntimeError("包含无效备份名称，已取消删除。")
    deleted_files = 0
    freed_bytes = 0
    for name in requested:
        database = paths.backup_dir / name
        for suffix in BACKUP_SUFFIXES:
            path = Path(str(database) + suffix)
            if path.exists():
                freed_bytes += path.stat().st_size
                path.unlink()
                deleted_files += 1
    return {"deleted_backups": len(requested), "deleted_files": deleted_files, "freed_bytes": freed_bytes}


def _csv(value: str) -> list[str]:
    return [item for item in value.split(",") if item]


def main() -> int:
    parser = argparse.ArgumentParser(description="Codex 历史记录管理服务")
    parser.add_argument("--codex-home")
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("threads")
    selections = subparsers.add_parser("save-selections")
    selections.add_argument("--ids", default="")
    sync = subparsers.add_parser("sync-selected")
    sync.add_argument("--ids", required=True)
    subparsers.add_parser("backups")
    delete = subparsers.add_parser("delete-backups")
    delete.add_argument("--names", required=True)
    args = parser.parse_args()
    paths = resolve_paths(args.codex_home)
    try:
        if args.command == "threads": result = list_threads(args.codex_home)
        elif args.command == "save-selections": result = save_selections(paths.codex_home, _csv(args.ids))
        elif args.command == "sync-selected": result = sync_selected(args.codex_home, _csv(args.ids))
        elif args.command == "backups": result = backup_items(args.codex_home)
        else: result = delete_backups(args.codex_home, _csv(args.names))
        result["ok"] = True
        print(to_json(result))
        return 0
    except Exception as exc:
        print(to_json({"ok": False, "error": str(exc)}))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
