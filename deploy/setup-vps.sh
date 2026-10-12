#!/usr/bin/env bash
# Only installs Hermland admin tools. Does not expose a web port or authorize any key.
set -euo pipefail
fail() { printf 'FAIL：%s\n' "$*" >&2; exit 1; }
upgrade=false
case ${1:-} in
    '') ;;
    --upgrade) upgrade=true ;;
    *) fail '用法：setup-vps.sh [--upgrade]；升级需管理员先核对差异' ;;
esac
[[ ${EUID} -eq 0 && -f /etc/os-release ]] || fail '请在 Debian/Ubuntu VPS 上以 root 运行'
. /etc/os-release
[[ "$ID" == debian || "$ID" == ubuntu ]] || fail '当前仅支持 Debian/Ubuntu'
for command in python3 sshd ssh-keygen systemctl ss; do
    command -v "$command" >/dev/null || fail "缺少 $command，先安装依赖"
done
sshd -t || fail '现有 SSH 配置无效，不安装'
systemctl is-active --quiet ssh || fail '需要运行中的 ssh.service'
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
python3 "$script_dir/ssh_policy.py"
target=/opt/hermland
[[ ! -L "$target" ]] || fail '工具目录不能是符号链接'
install -d -m 755 -o root -g root "$target"
for file in ssh-device.sh ssh-relay.sh ssh_policy.py hermland.py; do
    [[ -f "$script_dir/$file" && ! -L "$target/$file" ]] || fail "文件缺失或目标为符号链接：$file"
    [[ ! -e "$target/$file" || -f "$target/$file" ]] || fail "目标不是普通文件：$file"
    if [[ -e "$target/$file" ]] && ! cmp -s "$script_dir/$file" "$target/$file"; then
        [[ "$upgrade" == true ]] || fail "$target/$file 已有不同版本，不覆盖；人工确认后使用 --upgrade"
    fi
done
if [[ "$upgrade" == true ]]; then
    backup="$target/backups/$(date -u +%Y%m%dT%H%M%SZ)-$$"
    install -d -m 700 -o root -g root "$backup"
    for file in ssh-device.sh ssh-relay.sh ssh_policy.py hermland.py; do
        if [[ -f "$target/$file" ]]; then cp -p "$target/$file" "$backup/$file"; fi
    done
    printf '已备份原管理员工具：%s；没有迁移或授权任何设备\n' "$backup"
fi
for file in ssh-device.sh ssh-relay.sh ssh_policy.py hermland.py; do
    if [[ "$script_dir/$file" != "$target/$file" ]]; then
        install -m 755 -o root -g root "$script_dir/$file" "$target/$file"
    fi
done
printf 'PASS：管理员工具已安装，SSH 配置有效；尚未授权任何新设备或中转密钥\n'
printf '下一步：核对 Mini 公钥指纹，再运行 ssh-relay.sh authorize\n'
