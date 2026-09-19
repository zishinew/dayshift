#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
app_bundle="$project_dir/build/Dayshift.app"

cd "$project_dir"
swift build -c release --jobs 1
swift scripts/make-icon.swift "$project_dir/Resources/AppIcon.iconset"
# Finder and cloud-backed folders can attach extended attributes to generated
# resources; remove them so the resulting app can be signed and shared.
xattr -cr "$project_dir/Resources/AppIcon.iconset" "$project_dir/Resources/Info.plist" 2>/dev/null || true

rm -rf "$app_bundle"
mkdir -p "$app_bundle/Contents/MacOS" "$app_bundle/Contents/Resources"
cp "$project_dir/.build/release/DAYSHIFT" "$app_bundle/Contents/MacOS/DAYSHIFT"
cp "$project_dir/Resources/Info.plist" "$app_bundle/Contents/Info.plist"
iconutil --convert icns "$project_dir/Resources/AppIcon.iconset" --output "$app_bundle/Contents/Resources/AppIcon.icns"
xattr -cr "$app_bundle" 2>/dev/null || true
codesign --force --deep --sign - "$app_bundle"

echo "$app_bundle"
