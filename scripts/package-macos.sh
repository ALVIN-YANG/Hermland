#!/usr/bin/env bash
# Development artifacts are ad-hoc signed, not notarized for public distribution.
set -euo pipefail
fail() { printf 'FAIL：%s\n' "$*" >&2; exit 1; }
task_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$task_root"
mode=${1:-}
[[ "$mode" == --development || "$mode" == --signed ]] || fail '用法：package-macos.sh --development|--signed [输出目录]'
[[ $(uname -s) == Darwin ]] || fail '打包需要 macOS 与完整 Xcode'
command -v xcodegen >/dev/null || fail '请先安装 XcodeGen'
[[ -f LICENSE ]] || fail '缺少项目许可证，停止打包'
identity=-
suffix=-dev
hardened=NO
if [[ "$mode" == --signed ]]; then
    [[ -z $(git status --porcelain) ]] || fail '正式包必须来自干净的已提交源码'
    identity=${HERMLAND_SIGN_IDENTITY:-}
    [[ "$identity" == 'Developer ID Application:'* ]] || fail '需要 HERMLAND_SIGN_IDENTITY=Developer ID Application: …，不能用临时签名或 App Store 证书代替'
    [[ -n ${HERMLAND_NOTARY_PROFILE:-} ]] || fail '需要已由用户登记的 HERMLAND_NOTARY_PROFILE，不接受命令行明文密码'
    suffix=""
    hardened=YES
fi
task_package_dir=$(mktemp -d "${TMPDIR:-/tmp}/hermland-package.XXXXXXXX")
trap 'rm -rf "$task_package_dir"' EXIT
(cd macos && xcodegen generate)
xcodebuild -quiet -project macos/Hermland.xcodeproj -scheme Hermland -configuration Release \
    -destination 'generic/platform=macOS' -derivedDataPath "$task_package_dir/build" build \
    ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO CODE_SIGN_IDENTITY="$identity" \
    ENABLE_HARDENED_RUNTIME="$hardened" OTHER_CODE_SIGN_FLAGS="$( [[ "$mode" == --signed ]] && printf '%s' --timestamp || true )"
app="$task_package_dir/build/Build/Products/Release/Hermland.app"
codesign --verify --deep --strict "$app"
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app/Contents/Info.plist")
lipo "$app/Contents/MacOS/Hermland" -verify_arch arm64 x86_64
task_output=${2:-"$task_root/releases"}
mkdir -p "$task_output"
archive="$task_output/Hermland-$version$suffix.zip"
setup_archive="$task_output/HermlandSetup-$version$suffix.zip"
[[ ! -e "$archive" && ! -e "$setup_archive" ]] || fail '输出文件已存在，请使用新目录，不覆盖旧包'
if [[ "$mode" == --signed ]]; then
    ditto -c -k --keepParent "$app" "$task_package_dir/notarize.zip"
    xcrun notarytool submit "$task_package_dir/notarize.zip" --keychain-profile "$HERMLAND_NOTARY_PROFILE" \
        --wait --output-format json > "$task_package_dir/notary-result.json"
    python3 -c 'import json,sys; result=json.load(open(sys.argv[1])); sys.exit(0 if result.get("status")=="Accepted" else 1)' \
        "$task_package_dir/notary-result.json" || fail 'Apple 公证未通过，不生成正式发行包'
    xcrun stapler staple "$app"
    spctl --assess --type execute --verbose "$app"
fi
setup="$task_package_dir/HermlandSetup"
mkdir -p "$setup/deploy" "$setup/docs"
for name in hermland.py ssh_policy.py setup-vps.sh ssh-device.sh ssh-relay.sh connection.example.json connection.openclaw.example.json; do
    cp "deploy/$name" "$setup/deploy/"
done
for name in 快速开始 安全门禁 远程中转; do cp "docs/$name.md" "$setup/docs/"; done
cp README.md LICENSE "$setup/"
ditto -c -k --keepParent "$app" "$archive"
ditto -c -k --keepParent "$setup" "$setup_archive"
(cd "$task_output" && shasum -a 256 "$(basename "$archive")" "$(basename "$setup_archive")" > "SHA256SUMS$version$suffix.txt")
task_revision=$(git rev-parse HEAD)
task_dirty=false
[[ -z $(git status --porcelain) ]] || task_dirty=true
python3 -c 'import json,sys; print(json.dumps({"version":sys.argv[1],"sourceCommit":sys.argv[2],"dirtySource":sys.argv[3]=="true","mode":sys.argv[4],"architectures":["arm64","x86_64"],"notarized":sys.argv[4]=="--signed"},indent=2))' \
    "$version" "$task_revision" "$task_dirty" "$mode" > "$task_output/BUILD-$version$suffix.json"
printf 'PASS：%s\nPASS：%s\n' "$archive" "$setup_archive"
if [[ "$mode" == --development ]]; then
    printf '注意：开发测试包，临时签名、未公证。不能声称可直接分发给普通用户；不要关闭 Gatekeeper。\n'
fi
