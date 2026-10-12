#!/usr/bin/env bash
set -euo pipefail
task_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$task_root"
python3 -B -m unittest discover -s tests -p 'test_*.py' -v
bash -n deploy/*.sh tests/*.sh scripts/*.sh
git diff --check
if [[ ${1:-} == --macos ]]; then
    [[ $(uname -s) == Darwin ]] || { printf 'FAIL：--macos 需要 macOS\n' >&2; exit 1; }
    command -v xcodegen >/dev/null || { printf 'FAIL：请先安装 XcodeGen\n' >&2; exit 1; }
    task_check_dir=$(mktemp -d "${TMPDIR:-/tmp}/hermland-check.XXXXXXXX")
    trap 'rm -rf "$task_check_dir"' EXIT
    swiftc macos/Sources/AgentBackend.swift macos/Sources/SSHConfiguration.swift tests/SSHConfigurationCheck.swift -o "$task_check_dir/ssh-check"
    "$task_check_dir/ssh-check"
    (cd macos && xcodegen generate)
    xcodebuild -quiet -project macos/Hermland.xcodeproj -scheme Hermland -configuration Debug \
        -destination 'platform=macOS' -derivedDataPath macos/.build/check test \
        CODE_SIGN_IDENTITY=- -parallel-testing-enabled NO
fi
