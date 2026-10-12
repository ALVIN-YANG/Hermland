#!/usr/bin/env bash
# Live acceptance check; administrator SSH access must already be trusted and configured.
set -euo pipefail
host=${1:?用法：ssh-access-check.sh VPS地址 已授权设备用户}
actual_device=${2:?需要已授权设备用户}
[[ "$host" =~ ^[A-Za-z0-9.-]+$ && "$actual_device" =~ ^hl-[a-z0-9]{8,24}$ ]] || exit 2
test_dir=$(mktemp -d /tmp/hermland-ssh-check.XXXXXXXX)
device="hl-check$(basename "$test_dir" | shasum -a 256 | cut -c1-12)"
authorized=false
forward_pid=""
cleanup() {
    if [[ -n "$forward_pid" ]]; then kill "$forward_pid" 2>/dev/null || true; wait "$forward_pid" 2>/dev/null || true; fi
    if [[ "$authorized" == true ]]; then ssh -o BatchMode=yes "$host" "/opt/hermland/ssh-device.sh revoke $device" || true; fi
    rm -f "$test_dir/identity" "$test_dir/identity.pub" "$test_dir/known_hosts" "$test_dir/wrong_hosts" "$test_dir/check.log" "$test_dir/forward.log"
    rmdir "$test_dir"
}
trap cleanup EXIT
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
ssh-keygen -q -t ed25519 -N '' -C hermland-acceptance -f "$test_dir/identity"
# Obtain host identity through existing authenticated administrator SSH, not ssh-keyscan.
ssh -o BatchMode=yes "$host" 'cat /etc/ssh/ssh_host_ed25519_key.pub' | awk -v host="$host" '{ print host, $1, $2 }' > "$test_dir/known_hosts"
awk -v host="$host" '{ print host, $1, $2 }' "$test_dir/identity.pub" > "$test_dir/wrong_hosts"
opts=(-F /dev/null -T -i "$test_dir/identity" -o BatchMode=yes -o IdentitiesOnly=yes -o IdentityAgent=none -o StrictHostKeyChecking=yes -o GlobalKnownHostsFile=/dev/null -o UserKnownHostsFile="$test_dir/known_hosts" -o ConnectTimeout=8)
if ssh "${opts[@]}" "$actual_device@$host" true > "$test_dir/check.log" 2>&1; then fail '未授权密钥被接受'; fi
grep -q 'Permission denied' "$test_dir/check.log" || fail '未授权密钥测试未到达认证阶段'
printf 'PASS: 未授权设备密钥被拒绝\n'
scp -q "$test_dir/identity.pub" "$host:/opt/hermland/$device.pub"
ssh -o BatchMode=yes "$host" "/opt/hermland/ssh-device.sh authorize $device /opt/hermland/$device.pub"
authorized=true
# First occurrence wins for ssh -o; use a separate list for the wrong-host check.
wrong_opts=(-F /dev/null -T -i "$test_dir/identity" -o BatchMode=yes -o IdentitiesOnly=yes -o IdentityAgent=none -o StrictHostKeyChecking=yes -o GlobalKnownHostsFile=/dev/null -o UserKnownHostsFile="$test_dir/wrong_hosts" -o ConnectTimeout=8)
if ssh "${wrong_opts[@]}" "$device@$host" true > "$test_dir/check.log" 2>&1; then fail '错误服务器公钥被接受'; fi
grep -q 'Host key verification failed' "$test_dir/check.log" || fail '服务器身份测试未触发固定公钥校验'
printf 'PASS: 错误服务器公钥被拒绝\n'
if ssh "${opts[@]}" "$device@$host" 'printf SHELL_NOT_ALLOWED' > "$test_dir/check.log" 2>&1; then fail '设备获得 Shell'; fi
! grep -q 'SHELL_NOT_ALLOWED' "$test_dir/check.log" || fail '设备执行了命令'
printf 'PASS: 设备无法执行 Shell 命令\n'
if ssh "${opts[@]}" -W 127.0.0.1:22 "$device@$host" > "$test_dir/check.log" 2>&1; then fail '允许访问越权端口'; fi
grep -q 'administratively prohibited' "$test_dir/check.log" || fail '越权端口未被权限策略拒绝'
printf 'PASS: 转发到 VPS 的 SSH 端口被拒绝\n'
if ssh "${opts[@]}" -N -o ExitOnForwardFailure=yes -R 127.0.0.1:19124:127.0.0.1:19119 "$device@$host" > "$test_dir/check.log" 2>&1; then fail '设备获准创建反向隧道'; fi
grep -q 'remote port forwarding failed' "$test_dir/check.log" || fail '反向隧道未被拒绝'
printf 'PASS: 设备不能创建反向隧道\n'
ssh "${opts[@]}" -N -o ExitOnForwardFailure=yes -L 127.0.0.1:19123:127.0.0.1:19119 "$device@$host" > "$test_dir/forward.log" 2>&1 &
forward_pid=$!
ready=false
for _ in {1..20}; do
    if curl --max-time 2 -fsS http://127.0.0.1:19123/health > /dev/null 2>&1; then ready=true; break; fi
    kill -0 "$forward_pid" 2>/dev/null || fail '授权隧道异常退出'
    sleep 0.5
done
[[ "$ready" == true ]] || fail '授权隧道未到达 Mini'
printf 'PASS: 授权设备可经双通道访问 Mini 的健康接口\n'
ssh -o BatchMode=yes "$host" "/opt/hermland/ssh-device.sh revoke $device"
authorized=false
for _ in {1..20}; do
    kill -0 "$forward_pid" 2>/dev/null || break
    sleep 0.2
done
if kill -0 "$forward_pid" 2>/dev/null; then fail '撤销后现有隧道仍存活'; fi
wait "$forward_pid" 2>/dev/null || true
forward_pid=""
if ssh "${opts[@]}" "$device@$host" true > "$test_dir/check.log" 2>&1; then fail '撤销后设备仍可认证'; fi
grep -q 'Permission denied' "$test_dir/check.log" || fail '撤销后测试未到达认证阶段'
printf 'PASS: 撤销会关闭现有隧道，并阻止再次连接\n'
