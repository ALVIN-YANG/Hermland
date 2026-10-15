"""Run real upstream pages in a fresh container, without model keys or user state."""
import json
import os
from pathlib import Path
import secrets
import subprocess

assert Path("/.dockerenv").exists() and os.environ.get("HERMLAND_IOS_TEST") == "isolated"
state = Path("/tmp/hermland-upstreams")
state.mkdir(mode=0o700)
password, token = secrets.token_urlsafe(32), secrets.token_hex(32)
credentials = state / "test-credentials.json"
credentials.write_text(json.dumps({"password": password, "token": token}))
credentials.chmod(0o600)
config = state / "openclaw.json"
config.write_text(json.dumps({
    "gateway": {"mode": "local", "bind": "loopback", "port": 18789,
                "auth": {"mode": "token", "token": token}},
    "agents": {"defaults": {"workspace": str(state / "openclaw-workspace")}}
}))
config.chmod(0o600)
subprocess.Popen(["/opt/hermes-venv/bin/python", "/hermes/server.py"], env={
    **os.environ, "HERMES_HOME": str(state / "hermes"),
    "HERMES_WEBUI_STATE_DIR": str(state / "webui"),
    "HERMES_WEBUI_AGENT_DIR": str(state / "no-agent"),
    "HERMES_WEBUI_HOST": "127.0.0.1", "HERMES_WEBUI_PORT": "9000",
    "HERMES_WEBUI_PASSWORD": password, "HERMES_WEBUI_TEST_NETWORK_BLOCK": "1"
})
subprocess.Popen(["node", "/usr/local/lib/node_modules/openclaw/openclaw.mjs", "gateway", "run"], env={
    **os.environ, "OPENCLAW_STATE_DIR": str(state / "openclaw"), "OPENCLAW_CONFIG_PATH": str(config)
})
Path("/run/sshd").mkdir(exist_ok=True)
Path("/etc/hermland/ssh-devices").mkdir(parents=True)
subprocess.run(["ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-f", "/tmp/hermland-test-host"], check=True)
subprocess.run(["useradd", "--no-create-home", "--shell", "/usr/sbin/nologin", "hl-upstream001"], check=True)
subprocess.run(["usermod", "--password", "*", "hl-upstream001"], check=True)
os.execv("/usr/sbin/sshd", ["/usr/sbin/sshd", "-D", "-e", "-h", "/tmp/hermland-test-host",
    "-o", "PasswordAuthentication=no", "-o", "KbdInteractiveAuthentication=no",
    "-o", "AuthenticationMethods=publickey", "-o", "AuthorizedKeysFile=/etc/hermland/ssh-devices/%u.pub",
    "-o", "ForceCommand=/bin/false", "-o", "PermitTTY=no", "-o", "AllowTcpForwarding=local",
    "-o", "GatewayPorts=no", "-o", "AllowAgentForwarding=no", "-o", "X11Forwarding=no", "-o", "PermitTunnel=no"])
