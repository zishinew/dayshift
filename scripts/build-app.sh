#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
app_bundle="$project_dir/build/DAYSHIFT.app"

cd "$project_dir"
swift build -c release --jobs 1
swift scripts/make-icon.swift "$project_dir/Resources/AppIcon.iconset"

rm -rf "$app_bundle"
mkdir -p "$app_bundle/Contents/MacOS" "$app_bundle/Contents/Resources"
cp "$project_dir/.build/release/DAYSHIFT" "$app_bundle/Contents/MacOS/DAYSHIFT"
cp "$project_dir/Resources/Info.plist" "$app_bundle/Contents/Info.plist"
iconutil --convert icns "$project_dir/Resources/AppIcon.iconset" --output "$app_bundle/Contents/Resources/AppIcon.icns"
codesign --force --deep --sign - "$app_bundle"

echo "$app_bundle"
