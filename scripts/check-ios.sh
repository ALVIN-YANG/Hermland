#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
command -v xcodegen >/dev/null || { echo '需要先安装 XcodeGen。' >&2; exit 1; }
xcodegen generate --spec ios/project.yml
swift test -j 4
xcodebuild -quiet -project ios/Hermland-iOS.xcodeproj -scheme Hermland-iOS \
  -configuration Debug -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath ios/.build/ci -clonedSourcePackagesDirPath .build/xcode-packages \
  CODE_SIGN_IDENTITY=- build
# Real SSH checks are deliberately opt-in and use only disposable test containers:
# HERMLAND_IOS_SSH_TEST=isolated swift test -j 4 --filter SSHIntegrationTests
