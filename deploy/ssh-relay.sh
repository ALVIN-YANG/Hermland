#!/usr/bin/env bash
# Dedicated publisher account. Run on the VPS only after confirming the Mini public key.
set -euo pipefail
fail() { printf 'FAIL：%s\n' "$*" >&2; exit 1; }
[[ ${EUID} -eq 0 ]] || fail '请在 VPS 上以 root 运行'
action=${1:-}; key_file=${2:-}; relay_port=${3:-19119}
account=hl-relay
group=hermland-relay
key_dir=/etc/hermland/ssh-relay
config=/etc/ssh/sshd_config
marker='# Hermland relay access (managed)'
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

[[ "$action" == authorize ]] || fail '用法：ssh-relay.sh authorize Mini公钥文件 [VPS本机端口]'
[[ "$relay_port" =~ ^[0-9]{1,5}$ ]] && ((relay_port >= 1 && relay_port <= 65535)) || fail '端口无效'
[[ -f "$key_file" && $(awk 'NF {count++} END {print count+0}' "$key_file") -eq 1 ]] || fail '需要单个公钥文件'
read -r algorithm encoded _ < "$key_file"
[[ "$algorithm" == ssh-ed25519 && "$encoded" =~ ^[A-Za-z0-9+/]+={0,2}$ ]] || fail '仅接受 Ed25519 公钥'
ssh-keygen -lf "$key_file" >/dev/null || fail '公钥格式无效'
sshd -t || fail '现有 SSH 配置无效，先修复，不做修改'
systemctl is-active --quiet ssh || fail '需要运行中的 ssh.service'
python3 "$script_dir/ssh_policy.py" --config "$config"
[[ -x /usr/sbin/nologin ]] || fail '缺少 /usr/sbin/nologin，停止操作'
target="$key_dir/$account.pub"
expected="restrict,port-forwarding,command=\"/bin/false\",permitlisten=\"127.0.0.1:$relay_port\" $algorithm $encoded $account"
legacy="restrict,port-forwarding,permitlisten=\"127.0.0.1:$relay_port\" $algorithm $encoded $account"
if [[ -e "$target" ]]; then
    [[ "$(<"$target")" == "$expected" || "$(<"$target")" == "$legacy" ]] || fail '已有不同中转授权，停止操作，不覆盖'
fi
if id "$account" >/dev/null 2>&1; then
    id -nG "$account" | tr ' ' '\n' | grep -qx "$group" || fail '同名账户不属于 Hermland，停止操作'
else
    getent group "$group" >/dev/null || groupadd --system "$group"
    useradd --no-create-home --home-dir /var/empty/hermland --shell /usr/sbin/nologin --gid "$group" "$account"
    usermod --password '*' "$account"
fi
install -d -m 755 -o root -g root "$key_dir" /var/empty/hermland
backup="${config}.hermland-relay-backup-$(date -u +%Y%m%dT%H%M%SZ)-$$"
cp -p "$config" "$backup"
if ! grep -qxF "$marker" "$config"; then
    printf '\n%s\n' "$marker" >> "$config"
    printf '%s\n' \
        "Match Group $group" \
        '    AuthenticationMethods publickey' \
        '    PubkeyAuthentication yes' \
        '    PasswordAuthentication no' \
        '    KbdInteractiveAuthentication no' \
        "    AuthorizedKeysFile $key_dir/%u.pub" \
        '    AuthorizedKeysCommand none' \
        '    ForceCommand /bin/false' \
        '    PermitTTY no' \
        '    AllowAgentForwarding no' \
        '    X11Forwarding no' \
        '    AllowTcpForwarding remote' \
        '    AllowStreamLocalForwarding no' \
        '    PermitOpen none' \
        "    PermitListen 127.0.0.1:$relay_port" \
        '    GatewayPorts no' \
        '    PermitTunnel no' \
        '    PermitUserRC no' >> "$config"
fi
if ! sshd -t; then
    cp -p "$backup" "$config"
    fail 'SSH 配置验证失败，已恢复配置'
fi
# Verify the effective account policy, not just valid SSH syntax.
policy=$(sshd -T -C "user=$account,host=localhost,addr=127.0.0.1")
for required in 'authenticationmethods publickey' 'forcecommand /bin/false' 'passwordauthentication no' 'kbdinteractiveauthentication no' 'permittty no' 'allowagentforwarding no' 'x11forwarding no' 'allowtcpforwarding remote' 'allowstreamlocalforwarding no' 'permitopen none' "permitlisten 127.0.0.1:$relay_port" 'gatewayports no' 'permittunnel no' 'permituserrc no' "authorizedkeysfile $key_dir/%u.pub" 'authorizedkeyscommand none'; do
    if ! grep -qxF "$required" <<< "$policy"; then
        cp -p "$backup" "$config"
        fail "账户的实际 SSH 策略不匹配：$required；已恢复配置，没有写入新授权"
    fi
done
usermod --shell /usr/sbin/nologin "$account"
printf '%s\n' "$expected" > "$target"
chown root:root "$target"
chmod 644 "$target"
systemctl reload ssh
printf 'PASS：%s 只能建立 VPS 127.0.0.1:%s 的反向转发，不能执行 Shell\n' "$account" "$relay_port"
ssh-keygen -lf "$target"
