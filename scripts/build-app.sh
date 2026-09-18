#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
app_bundle="$project_dir/build/DAYSHIFT.app"

cd "$project_dir"
swift build -c release

rm -rf "$app_bundle"
mkdir -p "$app_bundle/Contents/MacOS" "$app_bundle/Contents/Resources"
cp "$project_dir/.build/release/DAYSHIFT" "$app_bundle/Contents/MacOS/DAYSHIFT"
cp "$project_dir/Resources/Info.plist" "$app_bundle/Contents/Info.plist"
codesign --force --deep --sign - "$app_bundle"

echo "$app_bundle"
