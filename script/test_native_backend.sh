#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
mkdir -p .build
swiftc -parse-as-library \
  macos/Models/AppPaths.swift macos/Models/Models.swift macos/Models/AccountModels.swift macos/Models/LocalConfig.swift macos/Support/AppConstants.swift \
  macos/Services/SQLiteDatabase.swift macos/Services/SessionService.swift \
  macos/Services/AccountServiceError.swift macos/Services/LocalConfigStore.swift \
  macos/Services/BackupService.swift macos/Services/HistoryService.swift \
  Tests/native_backend_check.swift -o .build/native-backend-check -lsqlite3
.build/native-backend-check
