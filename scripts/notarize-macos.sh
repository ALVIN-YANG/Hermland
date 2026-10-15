#!/usr/bin/env bash
# Keep the submission ID before waiting. A wait timeout must never trigger a new upload.
set -euo pipefail
fail() { printf 'FAIL：%s\n' "$*" >&2; exit 1; }
[[ $# == 3 && -f $1 && -d $3 && -n $2 ]] || fail '用法：notarize-macos.sh 候选ZIP 钥匙串配置 已存在的回执目录'
task_archive=$1
task_profile=$2
task_receipts=$3
[[ ! -e "$task_receipts/submission.json" ]] || fail '回执目录已有提交，请先查询原 ID，不重复上传'
if ! xcrun notarytool submit "$task_archive" --keychain-profile "$task_profile" --output-format json \
    > "$task_receipts/submission.json" 2> "$task_receipts/submit.stderr"; then
    fail "上传未确认；先核对 Apple history，不重复提交。回执：${task_receipts}"
fi
task_id=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("id", ""))' "$task_receipts/submission.json")
[[ "$task_id" =~ ^[0-9a-fA-F-]{36}$ ]] || fail "缺少可核对的提交 ID，先查 history。回执：${task_receipts}"
task_status_file="$task_receipts/wait-result.json"
if ! xcrun notarytool wait "$task_id" --keychain-profile "$task_profile" --timeout 20m --output-format json \
    > "$task_status_file" 2> "$task_receipts/wait.stderr"; then
    # A single read-only reconciliation covers a lost wait response, without uploading again.
    task_status_file="$task_receipts/recheck.json"
    xcrun notarytool info "$task_id" --keychain-profile "$task_profile" --output-format json \
        > "$task_status_file" 2> "$task_receipts/info.stderr" \
        || fail "公证等待未确认，保留 ID ${task_id}；稍后查询，不重复提交。回执：${task_receipts}"
fi
xcrun notarytool log "$task_id" --keychain-profile "$task_profile" "$task_receipts/log.json" \
    > /dev/null 2> "$task_receipts/log.stderr" || true
python3 -c 'import json,sys; r=json.load(open(sys.argv[1])); sys.exit(0 if r.get("id")==sys.argv[2] and r.get("status")=="Accepted" else 1)' \
    "$task_status_file" "$task_id" \
    || fail "Apple 尚未确认 Accepted；保留 ID ${task_id}，先查状态，不重复提交。回执：${task_receipts}"
cp "$task_status_file" "$task_receipts/result.json"
printf 'PASS：Apple 公证 Accepted，提交 ID %s\n' "$task_id"
