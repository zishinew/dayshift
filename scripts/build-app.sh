#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
app_bundle="$project_dir/build/Dayshift.app"
staging_dir="$(mktemp -d /tmp/dayshift-build.XXXXXX)"
staged_app="$staging_dir/Dayshift.app"
trap 'rm -rf "$staging_dir"' EXIT

cd "$project_dir"
swift build -c release --jobs 1
swift scripts/make-icon.swift "$project_dir/Resources/AppIcon.iconset"
# Finder and cloud-backed folders can attach extended attributes to generated
# resources; remove them so the resulting app can be signed and shared.
xattr -cr "$project_dir/Resources/AppIcon.iconset" "$project_dir/Resources/Info.plist" 2>/dev/null || true

mkdir -p "$staged_app/Contents/MacOS" "$staged_app/Contents/Resources"
cp "$project_dir/.build/release/DAYSHIFT" "$staged_app/Contents/MacOS/DAYSHIFT"
cp "$project_dir/Resources/Info.plist" "$staged_app/Contents/Info.plist"
iconutil --convert icns "$project_dir/Resources/AppIcon.iconset" --output "$staged_app/Contents/Resources/AppIcon.icns"
codesign --remove-signature "$staged_app/Contents/MacOS/DAYSHIFT" 2>/dev/null || true
xattr -cr "$staged_app" 2>/dev/null || true
codesign --force --sign - "$staged_app"
codesign --verify --strict "$staged_app"

rm -rf "$app_bundle"
mkdir -p "$project_dir/build"
ditto "$staged_app" "$app_bundle"

echo "$app_bundle"
