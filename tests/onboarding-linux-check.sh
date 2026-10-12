#!/usr/bin/env bash
# Destructive to an ephemeral container only. Never run this directly on a real VPS.
set -euo pipefail
[[ ${HERMLAND_ONBOARDING_TEST:-} == isolated && -f /.dockerenv && ${EUID} -eq 0 ]] || exit 2
source_dir=${1:?需要只读挂载的项目路径}
test_dir=$(mktemp -d /tmp/hermland-onboarding.XXXXXXXX)
fail() { printf 'FAIL：%s\n' "$*" >&2; exit 1; }
mkdir -p /run/sshd
ssh-keygen -A >/dev/null
/usr/sbin/sshd -o PidFile=/run/hermland-test-sshd.pid
export PATH="$source_dir/tests/fixtures:/usr/sbin:/usr/bin:/sbin:/bin"
bash "$source_dir/deploy/setup-vps.sh"
bash "$source_dir/deploy/setup-vps.sh"
[[ ! -e /etc/hermland/ssh-devices && ! -e /etc/hermland/ssh-relay ]] || fail '安装工具自动授权了密钥'
printf 'PASS：VPS 工具可重复安装，不自动授权\n'
printf '\n# older test version\n' >> /opt/hermland/hermland.py
cp -p /opt/hermland/hermland.py "$test_dir/older-tool.py"
if bash "$source_dir/deploy/setup-vps.sh"; then fail '默认安装覆盖了不同版本'; fi
cmp -s /opt/hermland/hermland.py "$test_dir/older-tool.py" || fail '默认安装改动了旧工具'
bash "$source_dir/deploy/setup-vps.sh" --upgrade
cmp -s /opt/hermland/hermland.py "$source_dir/deploy/hermland.py" || fail '明确升级没有安装新工具'
backup_match=false
for previous in /opt/hermland/backups/*/hermland.py; do
    if cmp -s "$previous" "$test_dir/older-tool.py"; then backup_match=true; fi
done
[[ "$backup_match" == true ]] || fail '明确升级没有保留原工具'
printf 'PASS：不同版本默认拒绝覆盖，明确升级保留可恢复备份\n'

ssh-keygen -q -t ed25519 -N '' -f "$test_dir/relay"
ssh-keygen -q -t ed25519 -N '' -f "$test_dir/device"
ssh-keygen -q -t ed25519 -N '' -f "$test_dir/wrong"
cp -p /etc/ssh/sshd_config "$test_dir/original.conf"
printf '\nMatch Address 203.0.113.0/24\n    ForceCommand none\n' >> /etc/ssh/sshd_config
cp -p /etc/ssh/sshd_config "$test_dir/conflict.conf"
if bash /opt/hermland/ssh-device.sh authorize hl-denied0001 "$test_dir/device.pub"; then fail '地址条件规则被错误接受'; fi
if bash /opt/hermland/ssh-relay.sh authorize "$test_dir/relay.pub"; then fail '中转授权忽略了条件规则'; fi
cmp -s /etc/ssh/sshd_config "$test_dir/conflict.conf" || fail '拒绝授权却改写了已有 SSH 配置'
! id hl-denied0001 >/dev/null 2>&1 || fail '拒绝授权却创建了设备账户'
[[ ! -e /etc/hermland/ssh-devices && ! -e /etc/hermland/ssh-relay ]] || fail '拒绝授权却写入了公钥'
cp -p "$test_dir/original.conf" /etc/ssh/sshd_config
printf 'PASS：外网 Match 冲突在任何账户、授权或配置写入前被拒绝\n'
bash /opt/hermland/ssh-relay.sh authorize "$test_dir/relay.pub"
bash /opt/hermland/ssh-relay.sh authorize "$test_dir/relay.pub"
if bash /opt/hermland/ssh-relay.sh authorize "$test_dir/wrong.pub"; then fail '覆盖了中转密钥'; fi
bash /opt/hermland/ssh-device.sh authorize hl-device0001 "$test_dir/device.pub"
bash /opt/hermland/ssh-device.sh authorize hl-device0001 "$test_dir/device.pub"
if bash /opt/hermland/ssh-device.sh authorize hl-device0001 "$test_dir/wrong.pub"; then fail '覆盖了设备密钥'; fi
printf 'PASS：授权可重复执行，不同密钥不能覆盖\n'

python3 /opt/hermland/hermland.py export --device hl-device0001 --host relay.example.com --output "$test_dir/connection.json"
python3 /opt/hermland/hermland.py export --device hl-device0001 --host relay.example.com --output "$test_dir/connection.json"
python3 -c 'import json,sys; c=json.load(open(sys.argv[1])); assert set(c)=={"host","port","user","remotePort","localPort","serverPublicKey"}; assert c["serverPublicKey"].startswith("ssh-ed25519 ")' "$test_dir/connection.json"
if python3 /opt/hermland/hermland.py export --device hl-notthere01 --host relay.example.com --output "$test_dir/unauthorized.json"; then fail '未授权设备导出了配置'; fi
printf 'PASS：配置自动生成且兼容 App 字段，没有隐含授权\n'

ssh-keygen -y -f /etc/ssh/ssh_host_ed25519_key > "$test_dir/host.pub"
awk '{print "127.0.0.1",$1,$2}' "$test_dir/host.pub" > "$test_dir/known_hosts"
opts=(-F /dev/null -T -o BatchMode=yes -o IdentitiesOnly=yes -o IdentityAgent=none -o StrictHostKeyChecking=yes -o UserKnownHostsFile="$test_dir/known_hosts" -o GlobalKnownHostsFile=/dev/null -o ConnectTimeout=3)
if ssh "${opts[@]}" -i "$test_dir/wrong" hl-device0001@127.0.0.1 true > "$test_dir/check.log" 2>&1; then fail '未授权密钥被接受'; fi
grep -q 'Permission denied' "$test_dir/check.log" || fail '未授权检查没有到达认证阶段'
for account in hl-relay hl-device0001; do
    identity="$test_dir/relay"
    [[ "$account" == hl-relay ]] || identity="$test_dir/device"
    if ssh "${opts[@]}" -i "$identity" "$account@127.0.0.1" 'printf SHELL_ALLOWED' > "$test_dir/check.log" 2>&1; then fail '账户获得 Shell'; fi
    ! grep -q SHELL_ALLOWED "$test_dir/check.log" || fail '账户执行了 Shell'
done
printf 'PASS：实际 SSH 拒绝未授权密钥，中转与设备账户均不能执行 Shell\n'
grep -qF 'command="/bin/false"' /etc/hermland/ssh-devices/hl-device0001.pub || fail '设备公钥缺少独立命令限制'
grep -qF 'command="/bin/false"' /etc/hermland/ssh-relay/hl-relay.pub || fail '中转公钥缺少独立命令限制'
[[ $(getent passwd hl-device0001 | cut -d: -f7) == /usr/sbin/nologin ]] || fail '设备账户仍有登录 Shell'
[[ $(getent passwd hl-relay | cut -d: -f7) == /usr/sbin/nologin ]] || fail '中转账户仍有登录 Shell'

python3 -c 'from http.server import BaseHTTPRequestHandler,HTTPServer
class Handler(BaseHTTPRequestHandler):
 def do_GET(self):
  self.send_response(200); self.end_headers(); self.wfile.write(b"{\"status\":\"ok\"}")
 def log_message(self,*args): pass
HTTPServer(("127.0.0.1",8787),Handler).serve_forever()' &
health_pid=$!
mkdir -p "$test_dir/keys with spaces"
cp -p "$test_dir/relay" "$test_dir/keys with spaces/identity"
cp "$test_dir/known_hosts" "$test_dir/keys with spaces/known_hosts"
python3 -c 'import argparse,importlib.util,pathlib,subprocess,sys
spec=importlib.util.spec_from_file_location("setup",sys.argv[1]); setup=importlib.util.module_from_spec(spec); spec.loader.exec_module(setup)
folder=pathlib.Path(sys.argv[2]); args=argparse.Namespace(host="127.0.0.1",ssh_port=22,relay_port=19119,backend_port=8787)
p=subprocess.Popen(setup.relay_arguments(args,folder/"identity",folder/"known_hosts"),stdout=subprocess.DEVNULL,stderr=subprocess.PIPE,text=True)
try:
 output=p.communicate(timeout=2)[1]
except subprocess.TimeoutExpired:
 p.terminate(); output=p.communicate(timeout=5)[1]
assert "remote forward success for: listen 127.0.0.1:" in output, output
print("PASS：真实 SSH 正确读取含空格目录的私钥与固定主机公钥")' /opt/hermland/hermland.py "$test_dir/keys with spaces"
ssh "${opts[@]}" -i "$test_dir/relay" -N -o ExitOnForwardFailure=yes -R 127.0.0.1:19119:127.0.0.1:8787 hl-relay@127.0.0.1 > "$test_dir/relay.log" 2>&1 &
relay_pid=$!
sleep 1
kill -0 "$relay_pid"
python3 /opt/hermland/hermland.py check --port 19119
if ssh "${opts[@]}" -i "$test_dir/relay" -W 127.0.0.1:22 hl-relay@127.0.0.1 > "$test_dir/check.log" 2>&1; then fail '中转账户可做本地转发'; fi
grep -q 'administratively prohibited' "$test_dir/check.log" || fail '本地转发没有被拒绝'
if ssh "${opts[@]}" -i "$test_dir/relay" -N -o ExitOnForwardFailure=yes -R 0.0.0.0:19120:127.0.0.1:8787 hl-relay@127.0.0.1 > "$test_dir/check.log" 2>&1; then fail '允许中转开放公网端口'; fi
grep -q 'remote port forwarding failed' "$test_dir/check.log" || fail '越权反向转发没有被拒绝'
printf 'PASS：中转只能发布指定回环端口，不能本地转发或发布其他端口\n'

ssh "${opts[@]}" -i "$test_dir/device" -N -o ExitOnForwardFailure=yes -L 127.0.0.1:19121:127.0.0.1:19119 hl-device0001@127.0.0.1 > "$test_dir/device.log" 2>&1 &
device_pid=$!
sleep 1
kill -0 "$device_pid"
python3 /opt/hermland/hermland.py check --port 19121
bash /opt/hermland/ssh-device.sh revoke hl-device0001
sleep 1
if kill -0 "$device_pid" 2>/dev/null; then fail '撤销后现有客户端隧道未关闭'; fi
if ssh "${opts[@]}" -i "$test_dir/device" hl-device0001@127.0.0.1 true > "$test_dir/check.log" 2>&1; then fail '撤销后设备仍能认证'; fi
grep -q 'Permission denied' "$test_dir/check.log" || fail '撤销检查没有到达认证阶段'
python3 /opt/hermland/hermland.py check --port 19119
kill "$relay_pid" "$health_pid"
printf 'PASS：双通道可达，撤销关闭客户端连接且不影响 Mini 中转\n'

if [[ -n ${OPENCLAW_ENTRY:-} ]]; then
    bash /opt/hermland/ssh-device.sh authorize hl-device0001 "$test_dir/device.pub"
    OPENCLAW_SSH_TEST_DIR="$test_dir" /usr/local/bin/node "$source_dir/tests/openclaw-integration-check.mjs"
    bash /opt/hermland/ssh-device.sh revoke hl-device0001
fi
