#!/usr/bin/env bash
# Development artifacts can be public previews, but are ad-hoc signed and not notarized.
set -euo pipefail
fail() { printf 'FAIL：%s\n' "$*" >&2; exit 1; }
task_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$task_root"
mode=${1:-}
[[ "$mode" == --development || "$mode" == --signed || "$mode" == --preflight ]] || fail '用法：package-macos.sh --development|--signed [输出目录]；--preflight 只检查正式发布条件'
[[ $(uname -s) == Darwin ]] || fail '打包需要 macOS 与完整 Xcode'
command -v xcodegen >/dev/null || fail '请先安装 XcodeGen'
[[ -f LICENSE ]] || fail '缺少项目许可证，停止打包'
task_revision=$(git rev-parse HEAD)
identity=-
suffix=-dev
hardened=NO
signing_team=""
if [[ "$mode" == --signed || "$mode" == --preflight ]]; then
    task_missing=0
    if [[ -n $(git status --porcelain) ]]; then
        printf 'FAIL：正式包必须来自干净的已提交源码\n' >&2
        task_missing=$((task_missing + 1))
    fi
    identity=${HERMLAND_SIGN_IDENTITY:-}
    if [[ "$identity" != 'Developer ID Application:'* ]]; then
        printf 'FAIL：需选择 Developer ID Application 证书并设置 HERMLAND_SIGN_IDENTITY；Apple Development/Distribution 不能替代\n' >&2
        task_missing=$((task_missing + 1))
    elif ! security find-identity -v -p codesigning | python3 -c 'import sys; name=sys.argv[1]; sys.exit(0 if any(line.rstrip().endswith(chr(34)+name+chr(34)) for line in sys.stdin) else 1)' "$identity"; then
        printf 'FAIL：所选 Developer ID Application 证书及其私钥在本机不可用\n' >&2
        task_missing=$((task_missing + 1))
    elif [[ "$identity" =~ \(([A-Z0-9]{10})\)$ ]]; then
        signing_team=${BASH_REMATCH[1]}
    else
        printf 'FAIL：证书名称缺少可核对的 Team ID，请使用完整名称\n' >&2
        task_missing=$((task_missing + 1))
    fi
    if [[ -z ${HERMLAND_NOTARY_PROFILE:-} ]]; then
        printf 'FAIL：需由用户本人登记 notarytool 钥匙串配置并设置 HERMLAND_NOTARY_PROFILE；不接受明文密码\n' >&2
        task_missing=$((task_missing + 1))
    fi
    [[ "$task_missing" == 0 ]] || fail '正式签名、公证条件未齐，不构建、不提交 Apple、不生成正式包'
    xcrun notarytool history --keychain-profile "$HERMLAND_NOTARY_PROFILE" --output-format json > /dev/null \
        || fail '公证配置未通过 Apple 只读认证；请核对会员、协议、Team ID 与应用专用密码'
    if [[ "$mode" == --preflight ]]; then
        printf 'PASS：源码干净，Developer ID 身份存在，公证账号认证通过；尚未构建或提交公证\n'
        exit 0
    fi
    suffix=""
    hardened=YES
fi
task_package_dir=$(mktemp -d "${TMPDIR:-/tmp}/hermland-package.XXXXXXXX")
trap 'rm -rf "$task_package_dir"' EXIT
(cd macos && xcodegen generate)
xcodebuild -quiet -project macos/Hermland.xcodeproj -scheme Hermland -configuration Release \
    -destination 'generic/platform=macOS' -derivedDataPath "$task_package_dir/build" build \
    ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO CODE_SIGN_IDENTITY="$identity" \
    ENABLE_TESTABILITY=NO CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO CODE_SIGN_STYLE=Manual \
    DEVELOPMENT_TEAM="$signing_team" ENABLE_HARDENED_RUNTIME="$hardened" \
    OTHER_CODE_SIGN_FLAGS="$( [[ "$mode" == --signed ]] && printf '%s' --timestamp || true )"
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
    python3 scripts/verify-macos-signature.py "$app" --developer-id
    # Keep receipts even on timeout/rejection, separate from public artifacts. Never store credentials here.
    task_notary_dir=$(mktemp -d "$task_output/.notary.XXXXXXXX")
    ditto -c -k --keepParent "$app" "$task_package_dir/notarize.zip"
    # Preserve the exact submitted candidate for later stapling if Apple's wait times out.
    ditto "$app" "$task_notary_dir/Hermland.app"
    cp "$task_package_dir/notarize.zip" "$task_notary_dir/submitted.zip"
    task_submit_exit=0
    xcrun notarytool submit "$task_package_dir/notarize.zip" --keychain-profile "$HERMLAND_NOTARY_PROFILE" \
        --wait --timeout 20m --output-format json > "$task_notary_dir/result.json" 2> "$task_notary_dir/submit.stderr" \
        || task_submit_exit=$?
    task_submission=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("id", ""))' \
        "$task_notary_dir/result.json" 2>/dev/null || true)
    if [[ "$task_submission" =~ ^[0-9a-fA-F-]{36}$ ]]; then
        xcrun notarytool log "$task_submission" --keychain-profile "$HERMLAND_NOTARY_PROFILE" \
            "$task_notary_dir/log.json" > /dev/null 2> "$task_notary_dir/log.stderr" || true
    fi
    [[ "$task_submit_exit" == 0 ]] || fail "Apple 提交/等待未确认成功，不生成正式包；原始签名候选与回执保留在 $task_notary_dir，先查状态，不盲目重复提交"
    python3 -c 'import json,sys; result=json.load(open(sys.argv[1])); sys.exit(0 if result.get("status")=="Accepted" else 1)' \
        "$task_notary_dir/result.json" || fail "Apple 公证未通过，不生成正式包；回执与诊断保留在 $task_notary_dir"
    xcrun stapler staple "$app"
    xcrun stapler validate "$app"
    spctl --assess --type execute --verbose "$app"
    if xcrun --find syspolicy_check > /dev/null 2>&1; then
        xcrun syspolicy_check distribution "$app"
    fi
else
    python3 scripts/verify-macos-signature.py "$app"
fi
if [[ "$mode" == --signed ]]; then
    [[ -z $(git status --porcelain) && $(git rev-parse HEAD) == "$task_revision" ]] \
        || fail "构建/公证期间源码改变，停止打包；不要把候选标成新提交，原候选保留在 $task_notary_dir"
fi
setup="$task_package_dir/HermlandSetup"
mkdir -p "$setup/deploy" "$setup/docs"
for name in hermland.py ssh_policy.py setup-vps.sh ssh-device.sh ssh-relay.sh connection.example.json connection.openclaw.example.json; do
    cp "deploy/$name" "$setup/deploy/"
done
for name in 快速开始 安全门禁 远程中转 发布与验收; do cp "docs/$name.md" "$setup/docs/"; done
cp README.md README.en.md LICENSE SECURITY.md CONTRIBUTING.md "$setup/"
mkdir -p "$setup/assets/readme"
cp assets/readme/panorama.png "$setup/assets/readme/"
cp assets/readme/how-it-works.svg assets/readme/how-it-works.en.svg "$setup/assets/readme/"
ditto -c -k --keepParent "$app" "$archive"
ditto -c -k --keepParent "$setup" "$setup_archive"
(cd "$task_output" && shasum -a 256 "$(basename "$archive")" "$(basename "$setup_archive")" > "SHA256SUMS$version$suffix.txt")
task_dirty=false
[[ -z $(git status --porcelain) ]] || task_dirty=true
if [[ "$mode" == --signed && ( "$task_dirty" == true || $(git rev-parse HEAD) != "$task_revision" ) ]]; then
    # Artifacts have not yet been reported as a completed release; retain them for diagnosis only.
    fail '打包期间源码改变，本次输出不能公开发行；检查后从干净源码重新打包'
fi
python3 -c 'import json,sys; print(json.dumps({"version":sys.argv[1],"sourceCommit":sys.argv[2],"dirtySource":sys.argv[3]=="true","mode":sys.argv[4],"architectures":["arm64","x86_64"],"notarized":sys.argv[4]=="--signed"},indent=2))' \
    "$version" "$task_revision" "$task_dirty" "$mode" > "$task_output/BUILD-$version$suffix.json"
printf 'PASS：%s\nPASS：%s\n' "$archive" "$setup_archive"
if [[ "$mode" == --development ]]; then
    printf '注意：临时签名、未公证。可作为明确标注的预览分发，不是公证正式版；不要关闭 Gatekeeper。\n'
fi
