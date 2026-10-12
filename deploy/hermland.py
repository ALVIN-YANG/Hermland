#!/usr/bin/env python3
"""Small, shared onboarding commands. Never handles model credentials or App keys."""
import argparse
import base64
import binascii
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import struct
import subprocess
import sys
import time
import urllib.request


class SetupError(Exception):
    pass


def require(condition, message):
    if not condition:
        raise SetupError(message)


def port(value):
    number = int(value)
    if not 1 <= number <= 65535:
        raise argparse.ArgumentTypeError("端口必须在 1–65535 之间")
    return number


def host(value):
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9.-]*", value):
        raise argparse.ArgumentTypeError("填写 IPv4 或域名，不能包含 SSH 选项或路径")
    return value


def public_key(text):
    parts = text.strip().split()
    require("\n" not in text.strip() and "\r" not in text.strip()
            and len(parts) >= 2 and parts[0] == "ssh-ed25519", "需要单个完整 Ed25519 公钥")
    try:
        raw = base64.b64decode(parts[1], validate=True)
    except (ValueError, binascii.Error):
        raise SetupError("公钥编码无效") from None
    require(len(raw) == 51 and raw[:19] == struct.pack(">I", 11) + b"ssh-ed25519" + struct.pack(">I", 32),
            "公钥格式无效")
    return f"ssh-ed25519 {parts[1]}"


def run(arguments, capture=False):
    result = subprocess.run(arguments, text=True, capture_output=capture)
    require(result.returncode == 0, f"命令失败：{arguments[0]}。停止本步，不跳过检查")
    return result.stdout if capture else ""


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def ui_path(value):
    if value == "/":
        return value
    if (not re.fullmatch(r"/[A-Za-z0-9._~/-]+", value) or "//" in value
            or any(part in (".", "..") for part in value.split("/"))):
        raise argparse.ArgumentTypeError("界面路径应为 / 或 /openclaw，不含完整地址、令牌或查询参数")
    return value.rstrip("/") + "/"


def health(number, backend="hermes", control_ui_path="/"):
    # Local checks must not go through environment HTTP proxies or follow redirects.
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())
    try:
        path = "/healthz" if backend == "openclaw" else "/health"
        request = urllib.request.Request(f"http://127.0.0.1:{number}{path}", headers={"Accept": "application/json"})
        with opener.open(request, timeout=3) as response:
            value = json.loads(response.read(65536))
            expected = "live" if backend == "openclaw" else "ok"
            require(response.status == 200 and isinstance(value, dict) and value.get("status") == expected
                    and (backend != "openclaw" or value.get("ok") is True), "健康接口未返回预期后端的响应")
        if backend == "openclaw":
            request = urllib.request.Request(f"http://127.0.0.1:{number}{control_ui_path}",
                                             headers={"Accept": "text/html"})
            with opener.open(request, timeout=3) as response:
                require(response.status == 200 and b"<openclaw-app" in response.read(1048576),
                        "Gateway 可达，但 Control UI 未启用或路径错误")
    except (OSError, ValueError) as exc:
        raise SetupError(f"127.0.0.1:{number} 健康检查失败；检查服务、端口和隧道") from exc


def listeners(number):
    if sys.platform == "darwin":
        result = subprocess.run(["/usr/sbin/lsof", "-nP", f"-iTCP:{number}", "-sTCP:LISTEN", "-F", "n"],
                                capture_output=True, text=True)
        require(result.returncode in (0, 1), "无法检查监听地址")
        return [line[1:] for line in result.stdout.splitlines() if line.startswith("n")]
    require(shutil.which("ss"), "缺少 ss，请安装 iproute2")
    text = run(["ss", "-H", "-lnt", "sport", "=", f":{number}"], capture=True)
    return [line.split()[3] for line in text.splitlines() if len(line.split()) >= 4]


def check_listener(number, backend="hermes", control_ui_path="/"):
    addresses = listeners(number)
    require(addresses, f"端口 {number} 未监听")
    allowed = {f"127.0.0.1:{number}", f"[::1]:{number}", f"::1:{number}"}
    require(f"127.0.0.1:{number}" in addresses and all(value in allowed for value in addresses),
            f"端口 {number} 不是仅绑定本机回环，停止配置；不要扩大监听范围")
    health(number, backend, control_ui_path)
    if backend == "openclaw":
        print(f"PASS：127.0.0.1:{number} 仅本机监听，/healthz 存活、Control UI 可加载；不代表已登录或模型可用")
    else:
        print(f"PASS：127.0.0.1:{number} 仅本机监听，/health 返回 status=ok")


def mac_user():
    require(sys.platform == "darwin" and os.getuid() != 0, "在常驻 Mac 的登录用户下执行，不要使用 sudo")


def state_dir():
    directory = Path.home() / "Library/Application Support/HermlandRelay"
    require(not directory.is_symlink(), "中转目录不能是符号链接")
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    directory.chmod(0o700)
    return directory


def save_new_or_same(path, content, mode=0o600):
    require(not path.is_symlink(), f"拒绝写入符号链接：{path.name}")
    if path.exists():
        require(path.read_bytes() == content, f"{path.name} 已有不同配置，停止操作；先人工确认，不覆盖")
        return
    with path.open("xb") as stream:
        os.chmod(path, mode)
        stream.write(content)


def relay_key():
    mac_user()
    identity = state_dir() / "identity"
    require(not identity.is_symlink() and not identity.with_suffix(".pub").is_symlink(), "拒绝使用符号链接密钥")
    if not identity.exists():
        require(not identity.with_suffix(".pub").exists(), "仅存在公钥，先检查原密钥，不自动替换")
        run(["/usr/bin/ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-C", "hermland-relay", "-f", str(identity)])
    identity.chmod(0o600)
    derived = public_key(run(["/usr/bin/ssh-keygen", "-y", "-P", "", "-f", str(identity)], capture=True))
    save_new_or_same(identity.with_suffix(".pub"), (derived + " hermland-relay\n").encode())
    print(f"PASS：中转密钥已准备，公钥文件：{identity.with_suffix('.pub')}")
    run(["/usr/bin/ssh-keygen", "-lf", str(identity.with_suffix(".pub"))])
    print("只发送 .pub 公钥；私钥留在常驻 Mac，不要发到聊天中")


def job(label, arguments, directory):
    return {
        "Label": label, "ProgramArguments": arguments, "RunAtLoad": True,
        "KeepAlive": True, "ThrottleInterval": 10,
        "WorkingDirectory": str(directory), "Umask": 0o077,
        "StandardOutPath": str(directory / f"{label}.out.log"),
        "StandardErrorPath": str(directory / f"{label}.err.log"),
    }


def install_job(value):
    agents = Path.home() / "Library/LaunchAgents"
    agents.mkdir(parents=True, exist_ok=True)
    path = agents / f"{value['Label']}.plist"
    save_new_or_same(path, plistlib.dumps(value))
    target = f"gui/{os.getuid()}"
    loaded = subprocess.run(["/bin/launchctl", "print", f"{target}/{value['Label']}"],
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if loaded.returncode != 0:
        run(["/bin/launchctl", "bootstrap", target, str(path)])
        run(["/bin/launchctl", "kickstart", f"{target}/{value['Label']}"])
    run(["/bin/launchctl", "print", f"{target}/{value['Label']}"], capture=True)
    print(f"PASS：登录启动服务已登记：{value['Label']}")


def backend_install(args):
    mac_user()
    if listeners(args.backend_port):
        check_listener(args.backend_port)
        print("复用已运行后端；没有改动原服务。请确认原服务已有登录启动设置")
        return
    webui = args.webui_dir.expanduser().resolve()
    require((webui / "bootstrap.py").is_file(), "找不到 bootstrap.py；先按快速开始安装 Hermes WebUI")
    # No unattended Agent install, model changes, or credential handling in launchd.
    directory = state_dir()
    value = job("land.hermland.onboarding-webui", [sys.executable, str(webui / "bootstrap.py"),
                str(args.backend_port), "--host", "127.0.0.1", "--no-browser", "--foreground", "--skip-agent-install"], directory)
    value["EnvironmentVariables"] = {"PATH": os.environ.get("PATH", "/usr/bin:/bin"),
        "HERMES_HOME": str(args.hermes_home.expanduser().resolve())}
    for name in ("HERMES_WEBUI_AGENT_DIR", "HERMES_WEBUI_STATE_DIR", "HERMES_WEBUI_PYTHON"):
        if os.environ.get(name):
            value["EnvironmentVariables"][name] = os.environ[name]
    install_job(value)
    deadline = time.monotonic() + 40
    while time.monotonic() < deadline:
        if listeners(args.backend_port):
            check_listener(args.backend_port)
            return
        time.sleep(2)
    raise SetupError("后端尚未就绪；查看本机服务日志，修复后重跑本步。不要删除 Hermes 数据")


def relay_arguments(args, identity, known_hosts):
    # ssh -o parses a config line: unlike -i, a path with spaces needs inner quotes.
    hosts_path = str(known_hosts).replace("\\", "\\\\").replace('"', '\\"')
    return ["/usr/bin/ssh", "-F", "/dev/null", "-N", "-T", "-v", "-p", str(args.ssh_port),
            "-i", str(identity), "-o", "BatchMode=yes", "-o", "IdentitiesOnly=yes", "-o", "IdentityAgent=none",
            "-o", "StrictHostKeyChecking=yes", "-o", "UpdateHostKeys=no", "-o", "GlobalKnownHostsFile=/dev/null",
            "-o", f'UserKnownHostsFile="{hosts_path}"', "-o", "ControlMaster=no", "-o", "ControlPath=none",
            "-o", "ExitOnForwardFailure=yes", "-o", "ConnectTimeout=8", "-o", "ServerAliveInterval=15",
            "-o", "ServerAliveCountMax=2", "-R", f"127.0.0.1:{args.relay_port}:127.0.0.1:{args.backend_port}",
            f"hl-relay@{args.host}"]


def relay_install(args):
    mac_user()
    check_listener(args.backend_port, args.backend, args.ui_path)
    directory = state_dir()
    identity = directory / "identity"
    require(identity.is_file() and not identity.is_symlink(), "先运行 relay-key，并由管理员授权中转公钥")
    key = public_key(args.server_key.read_text())
    name = args.host if args.ssh_port == 22 else f"[{args.host}]:{args.ssh_port}"
    known_hosts = directory / "known_hosts"
    save_new_or_same(known_hosts, f"{name} {key}\n".encode())
    value = job("land.hermland.onboarding-relay", relay_arguments(args, identity, known_hosts), directory)
    existing = Path.home() / "Library/LaunchAgents" / f"{value['Label']}.plist"
    if existing.exists():
        require(not existing.is_symlink() and existing.read_bytes() == plistlib.dumps(value),
                "已有不同的中转配置，停止操作，不覆盖")
        loaded = subprocess.run(["/bin/launchctl", "print", f"gui/{os.getuid()}/{value['Label']}"],
                                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if loaded.returncode == 0:
            print("PASS：相同中转服务已登记，没有重建连接；在 VPS 执行 check 验证当前链路")
            return
    # Probe one real reverse-forward request before registering a retrying service.
    with subprocess.Popen(relay_arguments(args, identity, known_hosts), stdout=subprocess.DEVNULL,
                          stderr=subprocess.PIPE, text=True) as probe:
        # -v reports successful forwarding; communicate timeout is bounded, no secrets printed.
        try:
            output = probe.communicate(timeout=12)[1]
        except subprocess.TimeoutExpired:
            probe.terminate()
            output = probe.communicate(timeout=5)[1]
        require("remote forward success for: listen 127.0.0.1:" in output,
                "中转认证或反向转发失败；检查公钥授权、服务器身份和 VPS 端口是否被占用")
    install_job(value)
    print("PASS：固定服务器身份，专用中转账户允许反向转发。下一步在 VPS 执行 check 验证整条链路")


def connection(args):
    require(sys.platform.startswith("linux") and os.geteuid() == 0, "在 VPS 上以 root 导出配置")
    require(re.fullmatch(r"hl-[a-z0-9]{8,24}", args.device), "设备名须为 hl- 加 8–24 位小写字母或数字")
    run([sys.executable, str(Path(__file__).with_name("ssh_policy.py"))])
    authorized = Path(f"/etc/hermland/ssh-devices/{args.device}.pub")
    require(authorized.is_file(), "设备尚未授权；导出配置不会自动授权设备")
    entry = authorized.read_text().strip().split()
    require(len(entry) >= 3 and entry[0] == f'restrict,port-forwarding,command="/bin/false",permitopen="127.0.0.1:{args.relay_port}"',
            "设备授权端口与配置不一致，或仍是旧版授权；请管理员用原公钥重新执行 authorize")
    public_key(" ".join(entry[1:]))
    groups = run(["id", "-nG", args.device], capture=True).split()
    require("hermland-devices" in groups, "设备账户不属于 Hermland")
    policy = run(["sshd", "-T", "-C", f"user={args.device},host=localhost,addr=127.0.0.1"], capture=True)
    for required in ("authenticationmethods publickey", "forcecommand /bin/false", "allowtcpforwarding local",
                     "permitlisten none", "passwordauthentication no"):
        require(required in policy.splitlines(), f"设备实际 SSH 策略不匹配：{required}")
    key = public_key(Path("/etc/ssh/ssh_host_ed25519_key.pub").read_text())
    value = {"host": args.host, "port": args.ssh_port, "user": args.device,
             "remotePort": args.relay_port, "localPort": args.local_port, "serverPublicKey": key}
    if args.backend == "openclaw":
        value.update(backend=args.backend, controlUIPath=args.ui_path)
    save_new_or_same(args.output.expanduser(), (json.dumps(value, indent=2) + "\n").encode())
    print(f"PASS：连接配置已导出到 {args.output}；不包含私钥、密码或模型 API Key")


def main():
    parser = argparse.ArgumentParser(description="Hermland 分步配置：每步失败停止，手动与 Agent 共用")
    commands = parser.add_subparsers(dest="command", required=True)
    check = commands.add_parser("check", help="检查本机监听范围和后端健康")
    check.add_argument("--port", type=port)
    commands.add_parser("relay-key", help="在常驻 Mac 准备专用中转公钥")
    backend = commands.add_parser("backend-install", help="复用已有后端或登记 macOS 登录启动服务")
    backend.add_argument("--webui-dir", type=Path, required=True)
    backend.add_argument("--backend-port", type=port, default=8787)
    backend.add_argument("--hermes-home", type=Path,
                         default=Path(os.environ.get("HERMES_HOME", str(Path.home() / ".hermes"))))
    relay = commands.add_parser("relay-install", help="在常驻 Mac 验证并登记反向 SSH 通道")
    relay.add_argument("--server-key", type=Path, required=True)
    relay.add_argument("--backend-port", type=port)
    export = commands.add_parser("export", help="在 VPS 导出已授权设备的 App 连接 JSON")
    export.add_argument("--device", required=True)
    export.add_argument("--output", type=Path, required=True)
    export.add_argument("--local-port", type=port, default=19121)
    for command in (check, relay, export):
        command.add_argument("--backend", choices=("hermes", "openclaw"), default="hermes")
        command.add_argument("--ui-path", type=ui_path, default="/", help="OpenClaw controlUi.basePath，默认 /")
    for command in (relay, export):
        command.add_argument("--host", type=host, required=True)
        command.add_argument("--ssh-port", type=port, default=22)
        command.add_argument("--relay-port", type=port, default=19119)
    args = parser.parse_args()
    if hasattr(args, "backend"):
        require(args.backend == "openclaw" or args.ui_path == "/", "Hermes WebUI 使用根路径 /")
        default_port = 18789 if args.backend == "openclaw" else 8787
        if args.command == "check" and args.port is None:
            args.port = default_port
        elif args.command == "relay-install" and args.backend_port is None:
            args.backend_port = default_port
    if args.command == "check":
        check_listener(args.port, args.backend, args.ui_path)
    elif args.command == "relay-key":
        relay_key()
    elif args.command == "backend-install":
        backend_install(args)
    elif args.command == "relay-install":
        relay_install(args)
    else:
        connection(args)


if __name__ == "__main__":
    try:
        main()
    except (SetupError, OSError, ValueError) as error:
        print(f"FAIL：{error}", file=sys.stderr)
        sys.exit(1)
