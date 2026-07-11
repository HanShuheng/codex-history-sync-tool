#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
mkdir -p .build
swiftc -parse-as-library \
  macos/Models/AccountModels.swift \
  macos/Services/AccountServiceError.swift \
  macos/Services/AccountUsageParser.swift \
  macos/Services/CodexAuthFile.swift \
  macos/Services/OAuthCallbackGate.swift \
  tests/account_pool_check.swift \
  -o .build/account-pool-check
.build/account-pool-check
