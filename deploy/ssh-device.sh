#!/usr/bin/env bash
# Run on the VPS as root. Each device gets a tunnel-only account for one loopback port.
set -euo pipefail

fail() { printf '%s\n' "$*" >&2; exit 1; }
[[ ${EUID} -eq 0 ]] || fail '请以 root 运行设备授权管理脚本'
action=${1:-}; device=${2:-}; key_file=${3:-}; relay_port=${4:-19119}
key_dir=/etc/hermland/ssh-devices
group=hermland-devices
config=/etc/ssh/sshd_config
marker='# Hermland device access (managed)'
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

validate_device() {
    [[ "$device" =~ ^hl-[a-z0-9]{8,24}$ ]] || fail '设备用户格式必须为 hl- 加 8–24 位小写字母或数字'
}

case "$action" in
    authorize)
        validate_device
        [[ "$relay_port" =~ ^[0-9]{1,5}$ ]] && (( relay_port >= 1 && relay_port <= 65535 )) || fail '转发端口无效'
        [[ -f "$key_file" && $(awk 'NF {count++} END {print count+0}' "$key_file") -eq 1 ]] || fail '需要单个设备公钥文件'
        read -r algorithm encoded _ < "$key_file"
        [[ "$algorithm" == ssh-ed25519 && "$encoded" =~ ^[A-Za-z0-9+/]+={0,2}$ ]] || fail '仅接受 Ed25519 公钥'
        ssh-keygen -lf "$key_file" >/dev/null || fail '公钥格式无效'
        sshd -t || fail '现有 SSH 配置无效，先修复，不做修改'
        systemctl is-active --quiet ssh || fail '需要运行中的 ssh.service'
        python3 "$script_dir/ssh_policy.py" --config "$config"
        [[ -x /usr/sbin/nologin ]] || fail '缺少 /usr/sbin/nologin，停止操作'
        getent group "$group" >/dev/null || groupadd --system "$group"
        if id "$device" >/dev/null 2>&1; then
            id -nG "$device" | tr ' ' '\n' | grep -qx "$group" || fail '已有同名账户不属于 Hermland，停止操作'
        else
            useradd --no-create-home --home-dir /var/empty/hermland --shell /usr/sbin/nologin --gid "$group" "$device"
            usermod --password '*' "$device"
        fi
        install -d -m 755 -o root -g root "$key_dir" /var/empty/hermland
        target="$key_dir/$device.pub"
        if [[ -e "$target" ]]; then
            grep -qF " $encoded " "$target" || fail '此设备已有不同公钥，请先撤销再授权'
        fi
        backup="${config}.hermland-backup-$(date -u +%Y%m%dT%H%M%SZ)"
        cp -p "$config" "$backup"
        # End-of-file Match avoids affecting global directives in existing drop-ins.
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
                '    AllowTcpForwarding local' \
                '    AllowStreamLocalForwarding no' \
                '    PermitListen none' \
                '    GatewayPorts no' \
                '    PermitTunnel no' \
                '    PermitUserRC no' >> "$config"
        fi
        if ! sshd -t; then
            cp -p "$backup" "$config"
            fail 'SSH 配置校验失败，已恢复原配置'
        fi
        policy=$(sshd -T -C "user=$device,host=localhost,addr=127.0.0.1")
        for required in 'authenticationmethods publickey' 'forcecommand /bin/false' 'passwordauthentication no' 'kbdinteractiveauthentication no' 'permittty no' 'allowagentforwarding no' 'x11forwarding no' 'allowtcpforwarding local' 'allowstreamlocalforwarding no' 'permitlisten none' 'gatewayports no' 'permittunnel no' 'permituserrc no' "authorizedkeysfile $key_dir/%u.pub" 'authorizedkeyscommand none'; do
            if ! grep -qxF "$required" <<< "$policy"; then
                cp -p "$backup" "$config"
                fail "账户的实际 SSH 策略不匹配：$required；已恢复配置，没有写入新授权"
            fi
        done
        # Independent command denial even if ForceCommand is accidentally removed later.
        usermod --shell /usr/sbin/nologin "$device"
        printf 'restrict,port-forwarding,command="/bin/false",permitopen="127.0.0.1:%s" %s %s %s\n' "$relay_port" "$algorithm" "$encoded" "$device" > "$target"
        chown root:root "$target"
        chmod 644 "$target"
        systemctl reload ssh
        printf '已授权 %s，只允许转发到 127.0.0.1:%s\n' "$device" "$relay_port"
        ssh-keygen -lf "$target"
        ;;
    revoke)
        validate_device
        [[ -f "$key_dir/$device.pub" ]] || fail '未找到这个设备的授权'
        id -nG "$device" | tr ' ' '\n' | grep -qx "$group" || fail '账户不属于 Hermland，停止操作'
        # Recoverable public-key record; active sessions must be closed as well.
        mv "$key_dir/$device.pub" "$key_dir/$device.revoked-$(date -u +%Y%m%dT%H%M%SZ)"
        pkill -TERM -u "$(id -u "$device")" || [[ $? -eq 1 ]]
        printf '已撤销 %s，并断开其现有连接；保留授权记录用于恢复\n' "$device"
        ;;
    list)
        if [[ -d "$key_dir" ]]; then
            while IFS= read -r file; do
                printf '%s ' "$(basename "$file" .pub)"
                ssh-keygen -lf "$file"
            done < <(find "$key_dir" -maxdepth 1 -type f -name 'hl-*.pub' | sort)
        fi
        ;;
    *)
        fail '用法：ssh-device.sh authorize hl-设备ID 公钥文件 [VPS本机端口] | revoke hl-设备ID | list'
        ;;
esac
