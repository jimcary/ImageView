#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

app_name="Imageview"
app_path="$repo_root/dist/$app_name.app"
staging_path="$repo_root/dist/.$app_name.app"
resources_path="$staging_path/Contents/Resources"
clang_cache="/private/tmp/imageview-clang-cache"

mkdir -p "$repo_root/dist" "$clang_cache"
trap 'rm -rf "$staging_path"' EXIT

for architecture in x86_64 arm64; do
    target="$architecture-apple-macosx"
    CLANG_MODULE_CACHE_PATH="$clang_cache" swift build --disable-sandbox --configuration release --triple "$target"
    test -x "$repo_root/.build/$target/release/$app_name"
done

rm -rf "$staging_path"
mkdir -p "$staging_path/Contents/MacOS" "$resources_path"

lipo -create \
    "$repo_root/.build/x86_64-apple-macosx/release/$app_name" \
    "$repo_root/.build/arm64-apple-macosx/release/$app_name" \
    -output "$staging_path/Contents/MacOS/$app_name"

cp "$repo_root/Info.plist" "$staging_path/Contents/Info.plist"
cp -R "$repo_root/Sources/ImageviewApp/Resources/en.lproj" "$resources_path/"
cp -R "$repo_root/Sources/ImageviewApp/Resources/zh-Hans.lproj" "$resources_path/"
cp "$repo_root/Imageview.icns" "$resources_path/Imageview.icns"
install -m 644 "$repo_root/.build/checkouts/libwebp-Xcode/libwebp/COPYING" "$resources_path/libwebp-LICENSE.txt"
install -m 644 "$repo_root/.build/checkouts/libwebp-Xcode/libwebp/PATENTS" "$resources_path/libwebp-PATENTS.txt"

xattr -cr "$staging_path"
codesign --force --deep --sign - "$staging_path"
rm -rf "$app_path"
mv "$staging_path" "$app_path"
trap - EXIT

echo "Built $app_path"
