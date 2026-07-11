#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
mkdir -p "$ROOT/.build"
xcrun swiftc "$ROOT"/macos/*.swift -o "$ROOT/.build/codex-history-sync"
exec "$ROOT/.build/codex-history-sync"
