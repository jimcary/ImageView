#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
app_path="$repo_root/dist/Imageview.app"
executable="$app_path/Contents/MacOS/Imageview"

test -x "$executable"
test -f "$app_path/Contents/Info.plist"
test -f "$app_path/Contents/Resources/en.lproj/Localizable.strings"
test -f "$app_path/Contents/Resources/zh-Hans.lproj/Localizable.strings"
lipo "$executable" -verify_arch x86_64 arm64
codesign --verify --deep --strict "$app_path"

"$executable" &
app_pid=$!
trap 'kill "$app_pid" 2>/dev/null || true; wait "$app_pid" 2>/dev/null || true' EXIT
sleep 1
kill -0 "$app_pid"

echo "Imageview smoke test passed"
