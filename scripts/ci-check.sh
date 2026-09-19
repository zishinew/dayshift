#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
cd "$project_dir"

swift package clean
swift test --jobs 1 -Xswiftc -swift-version -Xswiftc 5
./scripts/build-app.sh
codesign --verify --strict "$project_dir/build/Dayshift.app"
