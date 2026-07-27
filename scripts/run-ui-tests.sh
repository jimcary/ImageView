#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
app_path="$repo_root/dist/Imageview.app"

"$repo_root/scripts/build-app.sh"
IMAGEVIEW_APP_PATH="$app_path" xcodebuild test \
    -project "$repo_root/Imageview.xcodeproj" \
    -scheme ImageviewAppUITests \
    -destination 'platform=macOS' \
    -derivedDataPath "$repo_root/DerivedData/ImageviewUITests"
