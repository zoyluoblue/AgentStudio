#!/usr/bin/env bash
# One-command dev loop: regenerate project, build, run unit + live tests.
# Live provider tests read credentials from tools/test.env (gitignored); without it they skip.
set -uo pipefail
cd "$(dirname "$0")/.."

[ -f tools/test.env ] && source tools/test.env

xcodegen generate >/dev/null

xcodebuild test \
  -project AgentStudio.xcodeproj -scheme AgentStudio \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 \
  | grep -E "Test Case .*(passed|failed|skipped)|→|error:|Testing failed|Executed [0-9]|\*\* TEST (SUCCEEDED|FAILED)"
